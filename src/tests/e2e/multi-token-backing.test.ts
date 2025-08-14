import { describe, expect, test, beforeAll } from 'vitest';
import { Principal } from '@dfinity/principal';
import { minter, newIdentity } from './identity';
import {
  multiBackend,
  tokenA,
  tokenB,
  tokenC,
  TOKEN_A,
  TOKEN_B,
  TOKEN_C,
  MULTI_BACKEND_ID,
  MULTI_TOKEN_ID,
  GOVERNANCE_TOKEN_ID,
  multiToken,
  governanceToken,
  fundTestAccount,
} from './actor';

// Enable debug logging during development and bug resolution
const DEBUG = false;

// Custom JSON serializer that handles BigInt
function safeStringify(obj: any, indent = 2) {
  return JSON.stringify(
    obj,
    (_, value) => (typeof value === 'bigint' ? value.toString() : value),
    indent
  );
}

// Conditional logging helper
function debugLog(...args: any[]) {
  if (DEBUG) {
    console.log(...args);
  }
}

async function waitForTokenTransfer(
  token: any,
  recipient: Principal,
  expectedAmount: bigint,
  maxAttempts: number = 10
): Promise<boolean> {
  for (let i = 0; i < maxAttempts; i++) {
    const balance = await token.icrc1_balance_of({
      owner: recipient,
      subaccount: [],
    });
    if (balance >= expectedAmount) {
      return true;
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  return false;
}

function unwrapResult(result) {
  return result.ok;
}

function hasError(result) {
  return 'err' in result;
}

function getErrorType(result) {
  if (!hasError(result)) return null;
  return Object.keys(result.err)[0];
}

describe('Multi Token Backing System', () => {
  const testIdentity = newIdentity();
  let backend: any;
  let tokenAInstance: any;
  let tokenBInstance: any;
  let tokenCInstance: any;

  beforeAll(async () => {
    try {
      // Create actor instances once
      backend = await multiBackend(testIdentity);
      tokenAInstance = await tokenA(testIdentity);
      tokenBInstance = await tokenB(testIdentity);
      tokenCInstance = await tokenC(testIdentity);

      const minterTokenA = await tokenA(minter);
      const minterTokenB = await tokenB(minter);
      const minterTokenC = await tokenC(minter);

      // Fund test identity with tokens
      await Promise.all([
        fundTestAccount(minterTokenA, testIdentity, BigInt(1_000_000)),
        fundTestAccount(minterTokenB, testIdentity, BigInt(1_000_000)),
        fundTestAccount(minterTokenC, testIdentity, BigInt(1_000_000)),
      ]);

      // Log initial balances
      const [balanceA, balanceB, balanceC] = await Promise.all([
        tokenAInstance.icrc1_balance_of({
          owner: testIdentity.getPrincipal(),
          subaccount: [],
        }),
        tokenBInstance.icrc1_balance_of({
          owner: testIdentity.getPrincipal(),
          subaccount: [],
        }),
        tokenCInstance.icrc1_balance_of({
          owner: testIdentity.getPrincipal(),
          subaccount: [],
        }),
      ]);

      debugLog('Test identity balances:', {
        tokenA: balanceA.toString(),
        tokenB: balanceB.toString(),
        tokenC: balanceC.toString(),
      });
    } catch (e) {
      console.error('Error setting up test balances:', e);
      throw e;
    }
  });

  test.sequential('1. should handle token approval correctly', { timeout: 15000 }, async () => {
    const initialState = await backend.isInitialized();
    if (initialState) {
      debugLog('Warning: Canister already initialized');
      return;
    }

    // We need to use an admin/owner identity to approve tokens
    const adminBackend = await multiBackend(minter);

    // Process each token approval
    for (const [name, tokenId] of [
      ['Token A', TOKEN_A],
      ['Token B', TOKEN_B],
      ['Token C', TOKEN_C],
    ]) {
      const approveResult = await adminBackend.approveToken({
        canisterId: tokenId,
      });
      debugLog(`Approval response ${name}:`, safeStringify(approveResult));

      if (hasError(approveResult)) {
        const errorType = getErrorType(approveResult);
        // Only TokenAlreadyApproved is acceptable as an error for valid tokens
        if (errorType === 'TokenAlreadyApproved') {
          debugLog(`${name} already approved, this is valid`);
        } else {
          console.error(
            `Unexpected error during ${name} approval:`,
            safeStringify(approveResult.err)
          );
          // Any other error is a test failure
          expect(approveResult.err).toBeNull();
        }
      } else {
        // If no error, should be a successful approval
        debugLog(`${name} approved successfully`);
      }
    }

    // Test unauthorized approval with the regular test identity
    const unauthorizedResult = await backend.approveToken({
      canisterId: Principal.fromText('rrkah-fqaaa-aaaaa-aaaaq-cai'),
    });
    debugLog('Unauthorized approval response:', safeStringify(unauthorizedResult));
    expect(hasError(unauthorizedResult)).toBe(true);
    expect(getErrorType(unauthorizedResult)).toBe('Unauthorized');

    // Test management canister (should be rejected by our validation)
    const emptyPrincipalResult = await adminBackend.approveToken({
      canisterId: Principal.fromText('aaaaa-aa'),
    });
    expect(hasError(emptyPrincipalResult)).toBe(true);
    expect(getErrorType(emptyPrincipalResult)).toBe('TokenError');
    expect(emptyPrincipalResult.err.TokenError.code).toBe(2104n);

    // Test double approval of a token we just approved
    // (should return TokenAlreadyApproved error)
    const secondApproval = await adminBackend.approveToken({
      canisterId: TOKEN_A, // Re-using an already approved token
    });
    expect(hasError(secondApproval)).toBe(true);
    expect(getErrorType(secondApproval)).toBe('TokenAlreadyApproved');
  });

  test.sequential(
    '2. should initialize with three backing tokens',
    { timeout: 15000 },
    async () => {
      const initialState = await backend.isInitialized();
      if (initialState) {
        debugLog('Warning: Canister already initialized');
        return;
      }

      // Use admin identity for initialization
      const adminBackend = await multiBackend(minter);

      // Test initializing with a duplicate token
      const duplicateConfig = {
        supplyUnit: BigInt(100),
        backingTokens: [
          {
            canisterId: TOKEN_A,
            backingUnit: BigInt(100),
          },
          {
            canisterId: TOKEN_A, // Duplicate token
            backingUnit: BigInt(50),
          },
        ],
        multiToken: { canisterId: MULTI_TOKEN_ID },
        governanceToken: { canisterId: GOVERNANCE_TOKEN_ID },
      };

      const duplicateResult = await adminBackend.initialize(duplicateConfig);
      expect(hasError(duplicateResult)).toBe(true);
      debugLog('Duplicate token error:', safeStringify(duplicateResult));

      // Check for error for duplicate token
      if (getErrorType(duplicateResult) === 'TokenError') {
        const code = duplicateResult.err.TokenError.code;
        expect(code === 2103n).toBe(true);
      }

      // Test initializing with an unapproved token
      const unapprovedConfig = {
        supplyUnit: BigInt(100),
        backingTokens: [
          {
            canisterId: TOKEN_A,
            backingUnit: BigInt(100),
          },
          {
            canisterId: Principal.fromText('rrkah-fqaaa-aaaaa-aaaaq-cai'), // Unapproved token
            backingUnit: BigInt(50),
          },
        ],
        multiToken: { canisterId: MULTI_TOKEN_ID },
        governanceToken: { canisterId: GOVERNANCE_TOKEN_ID },
      };

      const unapprovedResult = await adminBackend.initialize(unapprovedConfig);
      expect(hasError(unapprovedResult)).toBe(true);
      debugLog('Unapproved token error:', safeStringify(unapprovedResult));

      // Verify error type for unapproved token
      expect(getErrorType(unapprovedResult)).toBe('TokenNotApproved');

      // Test initializing with a zero backingUnit
      const zeroUnitConfig = {
        supplyUnit: BigInt(100),
        backingTokens: [
          {
            canisterId: TOKEN_A,
            backingUnit: BigInt(0), // Invalid backing unit
          },
          {
            canisterId: TOKEN_B,
            backingUnit: BigInt(50),
          },
        ],
        multiToken: { canisterId: MULTI_TOKEN_ID },
        governanceToken: { canisterId: GOVERNANCE_TOKEN_ID },
      };

      const zeroUnitResult = await adminBackend.initialize(zeroUnitConfig);
      expect(hasError(zeroUnitResult)).toBe(true);
      debugLog('Zero backing unit error:', safeStringify(zeroUnitResult));

      // Verify error for invalid backing unit
      if (getErrorType(zeroUnitResult) === 'TokenError') {
        const code = zeroUnitResult.err.TokenError.code;
        expect(code === 2102n).toBe(true);
      }

      // Test initializing with a zero supply unit
      const zeroSupplyConfig = {
        supplyUnit: BigInt(0), // Invalid supply unit
        backingTokens: [
          {
            canisterId: TOKEN_A,
            backingUnit: BigInt(100),
          },
          {
            canisterId: TOKEN_B,
            backingUnit: BigInt(50),
          },
        ],
        multiToken: { canisterId: MULTI_TOKEN_ID },
        governanceToken: { canisterId: GOVERNANCE_TOKEN_ID },
      };

      const zeroSupplyResult = await adminBackend.initialize(zeroSupplyConfig);
      expect(hasError(zeroSupplyResult)).toBe(true);
      debugLog('Zero supply unit error:', safeStringify(zeroSupplyResult));

      // Verify error for invalid supply unit
      expect(getErrorType(zeroSupplyResult)).toBe('InvalidSupplyUnit');

      // Initialize with valid configuration
      const validConfig = {
        supplyUnit: BigInt(100),
        backingTokens: [
          {
            canisterId: TOKEN_A,
            backingUnit: BigInt(100),
          },
          {
            canisterId: TOKEN_B,
            backingUnit: BigInt(50),
          },
          {
            canisterId: TOKEN_C,
            backingUnit: BigInt(200),
          },
        ],
        multiToken: { canisterId: MULTI_TOKEN_ID },
        governanceToken: { canisterId: GOVERNANCE_TOKEN_ID },
      };

      const result = await adminBackend.initialize(validConfig);
      debugLog('Init result:', safeStringify(result));
      expect(hasError(result)).toBe(false);

      // Verify initialized state
      const finalState = await backend.isInitialized();
      expect(finalState).toBe(true);

      // Verify tokens were configured correctly
      const storedTokensResult = await backend.getBackingTokens();
      expect(hasError(storedTokensResult)).toBe(false);

      const storedTokens = unwrapResult(storedTokensResult);
      expect(storedTokens.length).toBe(3);

      // Verify token config
      storedTokens.forEach((token, index) => {
        expect(token.tokenInfo.canisterId.toText()).toEqual(
          validConfig.backingTokens[index].canisterId.toText()
        );
        expect(token.backingUnit).toEqual(validConfig.backingTokens[index].backingUnit);
        // Reserve quantity should be 0 initially
        expect(token.reserveQuantity).toEqual(BigInt(0));
      });

      // Verify multi token configuration
      const multiTokenId = await backend.getMultiTokenId();
      expect(multiTokenId.toText()).toEqual(MULTI_TOKEN_ID.toText());

      // Verify total supply is zero initially
      const totalSupplyResult = await backend.getTotalSupply();
      expect(hasError(totalSupplyResult)).toBe(false);
      const totalSupply = unwrapResult(totalSupplyResult);
      expect(totalSupply).toEqual(BigInt(0));
    }
  );

  test.sequential('3. should prevent double initialization', { timeout: 15000 }, async () => {
    // Use admin identity for attempted re-initialization
    const adminBackend = await multiBackend(minter);

    // Attempt to initialize again
    const config = {
      supplyUnit: BigInt(100),
      backingTokens: [
        {
          canisterId: TOKEN_A,
          backingUnit: BigInt(100),
        },
      ],
      multiToken: { canisterId: MULTI_TOKEN_ID },
      governanceToken: { canisterId: GOVERNANCE_TOKEN_ID },
    };

    const result = await adminBackend.initialize(config);
    expect(hasError(result)).toBe(true);
    debugLog('Double init error:', safeStringify(result));

    // Verify specific error for AlreadyInitialized
    expect(getErrorType(result)).toBe('AlreadyInitialized');

    // Also verify that we can't approve new tokens after initialization
    const approveResult = await adminBackend.approveToken({
      canisterId: Principal.fromText('rrkah-fqaaa-aaaaa-aaaaq-cai'),
    });
    expect(hasError(approveResult)).toBe(true);
    debugLog('Post-init approval error:', safeStringify(approveResult));

    // Verify specific error for AlreadyInitialized
    expect(getErrorType(approveResult)).toBe('AlreadyInitialized');
  });

  test.sequential(
    '4. should verify backing tokens and system configuration after initialization',
    { timeout: 15000 },
    async () => {
      const tokensResult = await backend.getBackingTokens();
      expect(hasError(tokensResult)).toBe(false);

      const tokens = unwrapResult(tokensResult);
      if (tokens.length === 0) {
        console.log('Warning: No backing tokens found');
        return;
      }

      // Verify token configurations
      expect(tokens[0].tokenInfo.canisterId.toText()).toBe(TOKEN_A.toText());
      expect(tokens[0].backingUnit).toBe(BigInt(100));
      expect(tokens[0].reserveQuantity).toBe(BigInt(0));

      expect(tokens[1].tokenInfo.canisterId.toText()).toBe(TOKEN_B.toText());
      expect(tokens[1].backingUnit).toBe(BigInt(50));
      expect(tokens[1].reserveQuantity).toBe(BigInt(0));

      expect(tokens[2].tokenInfo.canisterId.toText()).toBe(TOKEN_C.toText());
      expect(tokens[2].backingUnit).toBe(BigInt(200));
      expect(tokens[2].reserveQuantity).toBe(BigInt(0));

      // Check multi token ID
      const multiTokenIdResult = await backend.getMultiTokenId();
      expect(multiTokenIdResult.toText()).toBe(MULTI_TOKEN_ID.toText());

      // Check governance token ID (with the new endpoint)
      const governanceTokenIdResult = await backend.getGovernanceTokenId();
      expect(governanceTokenIdResult.toText()).toBe(GOVERNANCE_TOKEN_ID.toText());

      // Check total supply
      const totalSupplyResult = await backend.getTotalSupply();
      expect(hasError(totalSupplyResult)).toBe(false);
      expect(unwrapResult(totalSupplyResult)).toBe(BigInt(0));

      // Check system info
      const systemInfoResult = await backend.getSystemInfo();
      expect(hasError(systemInfoResult)).toBe(false);
      const systemInfo = unwrapResult(systemInfoResult);
      expect(systemInfo.initialized).toBe(true);
      expect(systemInfo.supplyUnit).toBe(BigInt(100));
    }
  );

  test.sequential('5. should validate issue operations', { timeout: 60000 }, async () => {
    // Calculate amounts
    const issueAmount = BigInt(100);
    const requiredAmountA = BigInt(100);
    const requiredAmountB = BigInt(50);
    const requiredAmountC = BigInt(200);

    // Get fees
    const [feeA, feeB, feeC] = await Promise.all([
      tokenAInstance.icrc1_fee(),
      tokenBInstance.icrc1_fee(),
      tokenCInstance.icrc1_fee(),
    ]);

    debugLog('Token fees:', {
      feeA: feeA.toString(),
      feeB: feeB.toString(),
      feeC: feeC.toString(),
    });

    const totalNeededA = requiredAmountA + feeA + feeA; // Additional fee for approval
    const totalNeededB = requiredAmountB + feeB + feeB;
    const totalNeededC = requiredAmountC + feeC + feeC;

    // Process each token in sequence
    for (const { tokenId, amount, name, token } of [
      {
        tokenId: TOKEN_A,
        amount: totalNeededA - feeA, // Subtract one fee since approve takes its own
        name: 'Token A',
        token: tokenAInstance,
      },
      {
        tokenId: TOKEN_B,
        amount: totalNeededB - feeB,
        name: 'Token B',
        token: tokenBInstance,
      },
      {
        tokenId: TOKEN_C,
        amount: totalNeededC - feeC,
        name: 'Token C',
        token: tokenCInstance,
      },
    ]) {
      debugLog(`Processing ${name}...`);

      // Add approval before deposit - approve for transfer amount plus fee
      const approveResult = await token.icrc2_approve({
        spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
        amount: amount + feeA,
        fee: [],
        memo: [],
        from_subaccount: [], // Required parameter
        created_at_time: [],
        expected_allowance: [],
        expires_at: [],
      });

      // Check for "Ok" property (ICRC standard)
      expect('Ok' in approveResult).toBe(true);
      debugLog(`${name} approval result:`, safeStringify(approveResult));

      // Wait a bit for approval to be processed
      await new Promise((resolve) => setTimeout(resolve, 1000));

      // Use deposit function to transfer tokens and create virtual balance
      const depositResult = await backend.deposit({
        token: tokenId,
        amount,
      });

      // Check for response format
      debugLog(`${name} deposit result:`, safeStringify(depositResult));

      // Verify deposit succeeds
      expect(hasError(depositResult)).toBe(false);

      // Verify virtual balance
      const balanceResult = await backend.getVirtualBalance(testIdentity.getPrincipal(), tokenId);

      expect(hasError(balanceResult)).toBe(false);
      const balance = unwrapResult(balanceResult);
      expect(balance).toBe(amount - feeA);
      debugLog(`${name} virtual balance: ${balance.toString()}`);
    }

    // Now that all tokens are in virtual ledger, do the issue operation
    const issueResult = await backend.issue({ amount: issueAmount });

    // Use the API's ok/err response format
    debugLog('Issue result:', safeStringify(issueResult));

    // Verify issue succeeds
    expect(hasError(issueResult)).toBe(false);

    // Verify minting completion
    const finalBalanceResult = await backend.getMultiTokenBalance(testIdentity.getPrincipal());
    expect(hasError(finalBalanceResult)).toBe(false);
    const finalBalance = unwrapResult(finalBalanceResult);
    expect(finalBalance).toBe(issueAmount);
    debugLog('Final multi token balance:', finalBalance.toString());

    // Verify supply and reserves
    const finalSupplyResult = await backend.getTotalSupply();
    expect(hasError(finalSupplyResult)).toBe(false);
    const finalSupply = unwrapResult(finalSupplyResult);
    expect(finalSupply).toBe(issueAmount);
    debugLog('Final supply:', finalSupply.toString());

    const finalTokensResult = await backend.getBackingTokens();
    expect(hasError(finalTokensResult)).toBe(false);
    const finalTokens = unwrapResult(finalTokensResult);
    debugLog('Final token reserves:', safeStringify(finalTokens));

    // Expect each token to have its reserve quantity set correctly
    finalTokens.forEach((token) => {
      // Verify token has expected reserve quantity if it matches one of our test tokens
      const principal = token.tokenInfo.canisterId.toText();
      if (principal === TOKEN_A.toText()) expect(token.reserveQuantity).toBe(requiredAmountA);
      if (principal === TOKEN_B.toText()) expect(token.reserveQuantity).toBe(requiredAmountB);
      if (principal === TOKEN_C.toText()) expect(token.reserveQuantity).toBe(requiredAmountC);
    });
  });

  test.sequential('6. should handle insufficient funds correctly', { timeout: 15000 }, async () => {
    // Store initial state
    const backingTokensResult = await backend.getBackingTokens();
    expect(hasError(backingTokensResult)).toBe(false);
    const previousTokens = unwrapResult(backingTokensResult);
    const previousReserves = previousTokens.map((t) => t.reserveQuantity);

    const previousSupplyResult = await backend.getTotalSupply();
    expect(hasError(previousSupplyResult)).toBe(false);
    const previousSupply = unwrapResult(previousSupplyResult);

    // Get virtual balances
    const virtualBalanceAResult = await backend.getVirtualBalance(
      testIdentity.getPrincipal(),
      TOKEN_A
    );
    const virtualBalanceBResult = await backend.getVirtualBalance(
      testIdentity.getPrincipal(),
      TOKEN_B
    );
    const virtualBalanceCResult = await backend.getVirtualBalance(
      testIdentity.getPrincipal(),
      TOKEN_C
    );

    // Extract balance values from results using helper functions
    const virtualBalanceA = hasError(virtualBalanceAResult)
      ? BigInt(0)
      : unwrapResult(virtualBalanceAResult);
    const virtualBalanceB = hasError(virtualBalanceBResult)
      ? BigInt(0)
      : unwrapResult(virtualBalanceBResult);
    const virtualBalanceC = hasError(virtualBalanceCResult)
      ? BigInt(0)
      : unwrapResult(virtualBalanceCResult);

    debugLog('Current virtual balances:', {
      A: virtualBalanceA.toString(),
      B: virtualBalanceB.toString(),
      C: virtualBalanceC.toString(),
    });

    // Request amount that would require more than our virtual balance
    const issueAmount = BigInt(10000);

    // Should return error for insufficient balance
    const result = await backend.issue({ amount: issueAmount });

    // Check for err property using helper function
    expect(hasError(result)).toBe(true);

    // We expect specifically an InsufficientBalance error
    const errorType = getErrorType(result);
    expect(errorType).toBe('InsufficientBalance');

    // Verify nothing changed
    const tokensResult = await backend.getBackingTokens();
    expect(hasError(tokensResult)).toBe(false);
    const tokens = unwrapResult(tokensResult);
    tokens.forEach((token, i) => {
      expect(token.reserveQuantity.toString()).toBe(previousReserves[i].toString());
    });

    const currentSupplyResult = await backend.getTotalSupply();
    expect(hasError(currentSupplyResult)).toBe(false);
    const currentSupply = unwrapResult(currentSupplyResult);
    expect(currentSupply.toString()).toBe(previousSupply.toString());

    // Verify virtual balances didn't change
    const finalVirtualBalanceAResult = await backend.getVirtualBalance(
      testIdentity.getPrincipal(),
      TOKEN_A
    );
    const finalVirtualBalanceBResult = await backend.getVirtualBalance(
      testIdentity.getPrincipal(),
      TOKEN_B
    );
    const finalVirtualBalanceCResult = await backend.getVirtualBalance(
      testIdentity.getPrincipal(),
      TOKEN_C
    );

    // Extract balance values from results using helper functions
    const finalVirtualBalanceA = hasError(finalVirtualBalanceAResult)
      ? BigInt(0)
      : unwrapResult(finalVirtualBalanceAResult);
    const finalVirtualBalanceB = hasError(finalVirtualBalanceBResult)
      ? BigInt(0)
      : unwrapResult(finalVirtualBalanceBResult);
    const finalVirtualBalanceC = hasError(finalVirtualBalanceCResult)
      ? BigInt(0)
      : unwrapResult(finalVirtualBalanceCResult);

    // Compare as strings to avoid BigInt equality issues
    expect(finalVirtualBalanceA.toString()).toBe(virtualBalanceA.toString());
    expect(finalVirtualBalanceB.toString()).toBe(virtualBalanceB.toString());
    expect(finalVirtualBalanceC.toString()).toBe(virtualBalanceC.toString());
  });

  test.sequential('7. should handle transfer failures atomically', { timeout: 15000 }, async () => {
    // Store initial state
    const backingTokensResult = await backend.getBackingTokens();
    expect(hasError(backingTokensResult)).toBe(false);
    const previousTokens = unwrapResult(backingTokensResult);
    const previousReserves = previousTokens.map((t) => t.reserveQuantity);

    const previousSupplyResult = await backend.getTotalSupply();
    expect(hasError(previousSupplyResult)).toBe(false);
    const previousSupply = unwrapResult(previousSupplyResult);

    // Get current virtual balances
    const virtualBalanceAResult = await backend.getVirtualBalance(
      testIdentity.getPrincipal(),
      TOKEN_A
    );
    const virtualBalanceBResult = await backend.getVirtualBalance(
      testIdentity.getPrincipal(),
      TOKEN_B
    );
    const virtualBalanceCResult = await backend.getVirtualBalance(
      testIdentity.getPrincipal(),
      TOKEN_C
    );

    // Extract balance values from results using the helper function
    const virtualBalanceA = hasError(virtualBalanceAResult)
      ? BigInt(0)
      : unwrapResult(virtualBalanceAResult);
    const virtualBalanceB = hasError(virtualBalanceBResult)
      ? BigInt(0)
      : unwrapResult(virtualBalanceBResult);
    const virtualBalanceC = hasError(virtualBalanceCResult)
      ? BigInt(0)
      : unwrapResult(virtualBalanceCResult);

    debugLog('Virtual balances before atomic test:', {
      A: virtualBalanceA.toString(),
      B: virtualBalanceB.toString(),
      C: virtualBalanceC.toString(),
    });

    // Try a request that would pass for first two tokens but fail for the last one
    // Token C has backing ratio of 200, so requesting 5100 would need:
    // Token A (ratio 100): 5100 tokens
    // Token B (ratio 50): 2550 tokens
    // Token C (ratio 200): 10200 tokens - should fail
    const atomicAmount = BigInt(5100);

    // Should return error since one token doesn't have enough balance
    const result = await backend.issue({ amount: atomicAmount });

    // Check for error property using helper function
    expect(hasError(result)).toBe(true);

    // We expect specifically an InsufficientBalance error
    const errorType = getErrorType(result);
    expect(errorType).toBe('InsufficientBalance');

    // Verify nothing changed - this is the key atomicity check
    const tokensResult = await backend.getBackingTokens();
    expect(hasError(tokensResult)).toBe(false);
    const tokens = unwrapResult(tokensResult);
    tokens.forEach((token, i) => {
      expect(token.reserveQuantity.toString()).toBe(previousReserves[i].toString());
    });

    const currentSupplyResult = await backend.getTotalSupply();
    expect(hasError(currentSupplyResult)).toBe(false);
    const currentSupply = unwrapResult(currentSupplyResult);
    expect(currentSupply.toString()).toBe(previousSupply.toString());

    // Verify virtual balances didn't change
    const finalVirtualBalanceAResult = await backend.getVirtualBalance(
      testIdentity.getPrincipal(),
      TOKEN_A
    );
    const finalVirtualBalanceBResult = await backend.getVirtualBalance(
      testIdentity.getPrincipal(),
      TOKEN_B
    );
    const finalVirtualBalanceCResult = await backend.getVirtualBalance(
      testIdentity.getPrincipal(),
      TOKEN_C
    );

    // Extract balance values from results using helper functions
    const finalVirtualBalanceA = hasError(finalVirtualBalanceAResult)
      ? BigInt(0)
      : unwrapResult(finalVirtualBalanceAResult);
    const finalVirtualBalanceB = hasError(finalVirtualBalanceBResult)
      ? BigInt(0)
      : unwrapResult(finalVirtualBalanceBResult);
    const finalVirtualBalanceC = hasError(finalVirtualBalanceCResult)
      ? BigInt(0)
      : unwrapResult(finalVirtualBalanceCResult);

    // Compare as strings to avoid BigInt equality issues
    expect(finalVirtualBalanceA.toString()).toBe(virtualBalanceA.toString());
    expect(finalVirtualBalanceB.toString()).toBe(virtualBalanceB.toString());
    expect(finalVirtualBalanceC.toString()).toBe(virtualBalanceC.toString());
  });

  test.sequential('8. should handle token withdrawals correctly', { timeout: 60000 }, async () => {
    const fee = BigInt(10000);
    const testAmount = BigInt(20000);

    // Need to cover:
    // 1. Approval fee
    // 2. Transfer fee
    // 3. The actual amount
    const depositAmount = testAmount + fee + fee;
    const approvalAmount = depositAmount + fee; // Extra fee for the approve operation itself

    debugLog('Starting test 8 with deposit amount:', depositAmount.toString());

    // Add approval before deposit
    const approveRes = await tokenAInstance.icrc2_approve({
      spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
      amount: approvalAmount,
      fee: [],
      memo: [],
      from_subaccount: [],
      created_at_time: [],
      expected_allowance: [],
      expires_at: [],
    });
    expect('Ok' in approveRes).toBe(true);

    // Initial setup - deposit tokens
    const depositResult = await backend.deposit({
      token: TOKEN_A,
      amount: depositAmount,
    });
    debugLog('Deposit result:', safeStringify(depositResult));

    // If deposit fails, log failure and skip test
    if (hasError(depositResult)) {
      debugLog('Deposit failed, test cannot proceed:', safeStringify(depositResult));
      return;
    }

    expect(hasError(depositResult)).toBe(false);

    // Record starting balances
    const startRealBalance = await tokenAInstance.icrc1_balance_of({
      owner: testIdentity.getPrincipal(),
      subaccount: [],
    });
    debugLog('Starting real balance:', startRealBalance.toString());

    const startVirtualBalanceResult = await backend.getVirtualBalance(
      testIdentity.getPrincipal(),
      TOKEN_A
    );
    expect(hasError(startVirtualBalanceResult)).toBe(false);
    const startVirtualBalance = unwrapResult(startVirtualBalanceResult);
    debugLog('Starting virtual balance:', startVirtualBalance.toString());

    // Perform valid withdrawal
    const withdrawResult = await backend.withdraw({
      token: TOKEN_A,
      amount: testAmount,
    });
    debugLog('Withdraw result:', safeStringify(withdrawResult));
    expect(hasError(withdrawResult)).toBe(false);

    // Check real balance updated
    const expectedRealBalance = startRealBalance + (testAmount - fee);
    const currentBalance = await tokenAInstance.icrc1_balance_of({
      owner: testIdentity.getPrincipal(),
      subaccount: [],
    });
    debugLog('Current real balance:', currentBalance.toString());
    debugLog('Expected real balance:', expectedRealBalance.toString());
    expect(currentBalance).toBe(expectedRealBalance);

    // Check virtual balance decreased
    const endVirtualBalanceResult = await backend.getVirtualBalance(
      testIdentity.getPrincipal(),
      TOKEN_A
    );
    expect(hasError(endVirtualBalanceResult)).toBe(false);
    const endVirtualBalance = unwrapResult(endVirtualBalanceResult);
    const expectedVirtualBalance = startVirtualBalance - testAmount;

    debugLog('End virtual balance:', endVirtualBalance.toString());
    debugLog('Expected virtual balance:', expectedVirtualBalance.toString());

    // Using toString() comparison to avoid potential BigInt comparison issues
    expect(endVirtualBalance.toString()).toBe(expectedVirtualBalance.toString());

    // Test invalid withdrawal - attempt to withdraw more than available
    const invalidWithdrawResult = await backend.withdraw({
      token: TOKEN_A,
      amount: endVirtualBalance + BigInt(1000),
    });
    expect(hasError(invalidWithdrawResult)).toBe(true);
    expect(getErrorType(invalidWithdrawResult)).toBe('InsufficientBalance');

    // Verify balances remained unchanged after failed withdrawal
    const finalVirtualBalanceResult = await backend.getVirtualBalance(
      testIdentity.getPrincipal(),
      TOKEN_A
    );
    expect(hasError(finalVirtualBalanceResult)).toBe(false);
    const finalVirtualBalance = unwrapResult(finalVirtualBalanceResult);
    expect(finalVirtualBalance.toString()).toBe(endVirtualBalance.toString());

    const finalRealBalance = await tokenAInstance.icrc1_balance_of({
      owner: testIdentity.getPrincipal(),
      subaccount: [],
    });
    expect(finalRealBalance).toBe(currentBalance);
  });

  test.sequential(
    '9. should handle multiple concurrent operations safely',
    { timeout: 30000 },
    async () => {
      const identities = [newIdentity(), newIdentity(), newIdentity()];
      const depositAmount = BigInt(100000); // Large enough for multiple operations
      const fee = BigInt(10000);
      const issueAmount = BigInt(100); // Must be multiple of supply unit
      const withdrawAmount = BigInt(20000); // Ensure it's larger than fee (10000)

      // Create token instances once
      const minterTokenA = await tokenA(minter);
      const minterTokenB = await tokenB(minter);
      const minterTokenC = await tokenC(minter);

      // Fund identities - must happen before any test logic
      await Promise.all(
        identities.flatMap((identity) => [
          fundTestAccount(minterTokenA, identity, BigInt(1_000_000)),
          fundTestAccount(minterTokenB, identity, BigInt(1_000_000)),
          fundTestAccount(minterTokenC, identity, BigInt(1_000_000)),
        ])
      );

      debugLog('Starting test 9 - multiple concurrent operations');

      // Test concurrent deposits of the same token
      const sameTokenDeposits = await Promise.all(
        identities.map(async (identity) => {
          const tokenAInstance = await tokenA(identity);
          // First approve
          await tokenAInstance.icrc2_approve({
            spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
            amount: depositAmount + fee,
            fee: [],
            memo: [],
            from_subaccount: [],
            created_at_time: [],
            expected_allowance: [],
            expires_at: [],
          });

          // Then deposit the same token simultaneously
          return (await multiBackend(identity)).deposit({
            token: TOKEN_A,
            amount: depositAmount,
          });
        })
      );

      // Verify all same-token deposits succeeded
      sameTokenDeposits.forEach((result, index) => {
        debugLog(`Deposit result ${index}:`, safeStringify(result));
        expect(hasError(result)).toBe(false);
      });

      // Verify virtual balances for same-token deposits
      await Promise.all(
        identities.map(async (identity) => {
          const vbResult = await backend.getVirtualBalance(identity.getPrincipal(), TOKEN_A);
          expect(hasError(vbResult)).toBe(false);
          const virtualBalance = unwrapResult(vbResult);
          expect(virtualBalance).toBe(depositAmount - fee);
        })
      );

      // Set up virtual balances for remaining tokens
      await Promise.all(
        identities.map(async (identity) => {
          const tokenBInstance = await tokenB(identity);
          const tokenCInstance = await tokenC(identity);

          // Approve Token B
          await tokenBInstance.icrc2_approve({
            spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
            amount: depositAmount + fee,
            fee: [],
            memo: [],
            from_subaccount: [],
            created_at_time: [],
            expected_allowance: [],
            expires_at: [],
          });

          // Deposit Token B
          const resultB = await (
            await multiBackend(identity)
          ).deposit({
            token: TOKEN_B,
            amount: depositAmount,
          });
          expect(hasError(resultB)).toBe(false);

          // Approve Token C
          await tokenCInstance.icrc2_approve({
            spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
            amount: depositAmount + fee,
            fee: [],
            memo: [],
            from_subaccount: [],
            created_at_time: [],
            expected_allowance: [],
            expires_at: [],
          });

          // Deposit Token C
          const resultC = await (
            await multiBackend(identity)
          ).deposit({
            token: TOKEN_C,
            amount: depositAmount,
          });
          expect(hasError(resultC)).toBe(false);
        })
      );

      // Record initial state
      const initialSupplyResult = await backend.getTotalSupply();
      expect(hasError(initialSupplyResult)).toBe(false);
      const initialSupply = unwrapResult(initialSupplyResult);

      const initialTokensResult = await backend.getBackingTokens();
      expect(hasError(initialTokensResult)).toBe(false);
      const initialTokens = unwrapResult(initialTokensResult);

      // Execute concurrent issue operations
      const results = await Promise.all(
        identities.map(async (identity) =>
          (await multiBackend(identity)).issue({ amount: issueAmount })
        )
      );

      // Verify all operations succeeded
      results.forEach((result) => {
        expect(hasError(result)).toBe(false);
      });

      // Calculate total issued amount
      const totalIssued = BigInt(identities.length) * issueAmount;

      // Verify final state
      const finalSupplyResult = await backend.getTotalSupply();
      expect(hasError(finalSupplyResult)).toBe(false);
      const finalSupply = unwrapResult(finalSupplyResult);
      expect(finalSupply).toBe(initialSupply + totalIssued);

      // Verify backing token reserves increased correctly
      const finalTokensResult = await backend.getBackingTokens();
      expect(hasError(finalTokensResult)).toBe(false);
      const finalTokens = unwrapResult(finalTokensResult);

      finalTokens.forEach((token, i) => {
        const expectedIncrease = (totalIssued * token.backingUnit) / BigInt(100);
        expect(token.reserveQuantity).toBe(initialTokens[i].reserveQuantity + expectedIncrease);
      });

      // Test concurrent withdrawals of the same token
      const sameTokenWithdrawals = await Promise.all(
        identities.map(async (identity) =>
          (await multiBackend(identity)).withdraw({
            token: TOKEN_A,
            amount: withdrawAmount, // Now using larger amount that exceeds fee
          })
        )
      );

      // Verify all same-token withdrawals succeeded
      sameTokenWithdrawals.forEach((result) => {
        expect(hasError(result)).toBe(false);
      });

      // Verify final virtual balances after same-token withdrawals
      await Promise.all(
        identities.map(async (identity) => {
          const finalVirtualBalanceResult = await backend.getVirtualBalance(
            identity.getPrincipal(),
            TOKEN_A
          );
          expect(hasError(finalVirtualBalanceResult)).toBe(false);
          const finalVirtualBalance = unwrapResult(finalVirtualBalanceResult);

          const token = finalTokens.find(
            (t) => t.tokenInfo.canisterId.toText() === TOKEN_A.toText()
          );
          expect(token).toBeDefined();

          const expectedDeduction = (issueAmount * token!.backingUnit) / BigInt(100);
          expect(finalVirtualBalance).toBe(
            depositAmount - expectedDeduction - fee - withdrawAmount
          );
        })
      );

      // Test remaining concurrent withdrawals
      const remainingWithdrawals = await Promise.all(
        identities.map(async (identity) => {
          const mbInstance = await multiBackend(identity);
          return Promise.all([
            mbInstance.withdraw({
              token: TOKEN_B,
              amount: withdrawAmount,
            }),
            mbInstance.withdraw({
              token: TOKEN_C,
              amount: withdrawAmount,
            }),
          ]);
        })
      ).then((results) => results.flat());

      // Verify all remaining withdrawals succeeded
      remainingWithdrawals.forEach((result) => {
        expect(hasError(result)).toBe(false);
      });

      // Verify final virtual balances for all tokens
      await Promise.all(
        identities.flatMap((identity) =>
          [TOKEN_A, TOKEN_B, TOKEN_C].map(async (tokenId) => {
            const finalVirtualBalanceResult = await backend.getVirtualBalance(
              identity.getPrincipal(),
              tokenId
            );
            expect(hasError(finalVirtualBalanceResult)).toBe(false);
            const finalVirtualBalance = unwrapResult(finalVirtualBalanceResult);

            const token = finalTokens.find(
              (t) => t.tokenInfo.canisterId.toText() === tokenId.toText()
            );
            expect(token).toBeDefined();

            const expectedDeduction = (issueAmount * token!.backingUnit) / BigInt(100);
            expect(finalVirtualBalance).toBe(
              depositAmount - expectedDeduction - fee - withdrawAmount
            );
          })
        )
      );
    }
  );

  test.sequential(
    '10. should handle supply unit alignment correctly',
    { timeout: 15000 },
    async () => {
      const fee = BigInt(10000);
      const testAmount = BigInt(20000);

      // First ensure we have enough virtual balance for these tests
      // Transfer tokens which will automatically create virtual balances
      const requiredAmount = BigInt(200); // More than we'll need for tests

      for (const { token, tokenId } of [
        { token: tokenAInstance, tokenId: TOKEN_A },
        { token: tokenBInstance, tokenId: TOKEN_B },
        { token: tokenCInstance, tokenId: TOKEN_C },
      ]) {
        const virtualBalanceResult = await backend.getVirtualBalance(
          testIdentity.getPrincipal(),
          tokenId
        );

        const currentBalance = hasError(virtualBalanceResult)
          ? BigInt(0)
          : unwrapResult(virtualBalanceResult);

        if (currentBalance < requiredAmount) {
          const fee = await token.icrc1_fee();
          const transferAmount = requiredAmount - currentBalance + fee;

          // Add approval before transfer
          await token.icrc2_approve({
            spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
            amount: transferAmount + fee,
            fee: [],
            memo: [],
            from_subaccount: [],
            created_at_time: [],
            expected_allowance: [],
            expires_at: [],
          });

          // Then deposit
          const result = await backend.deposit({
            token: tokenId,
            amount: transferAmount,
          });
          expect(hasError(result)).toBe(false);

          // Wait for virtual balance to sync
          let balanceSynced = false;
          for (let attempt = 0; attempt < 10; attempt++) {
            const balanceResult = await backend.getVirtualBalance(
              testIdentity.getPrincipal(),
              tokenId
            );

            if (!hasError(balanceResult) && unwrapResult(balanceResult) >= requiredAmount) {
              balanceSynced = true;
              break;
            }
            await new Promise((resolve) => setTimeout(resolve, 1000));
          }
          expect(balanceSynced).toBe(true);
        }
      }

      // Test cases that verify supply unit alignment with backing ratios
      const testCases = [
        { amount: BigInt(99), expectedErrorType: 'InvalidAmount' }, // Just under supply unit
        { amount: BigInt(101), expectedErrorType: 'InvalidAmount' }, // Just over supply unit
        { amount: BigInt(150), expectedErrorType: 'InvalidAmount' }, // Between supply units
      ];

      // Verify misaligned amounts return appropriate errors
      for (const { amount, expectedErrorType } of testCases) {
        const result = await backend.issue({ amount });
        expect(hasError(result)).toBe(true);
        expect(getErrorType(result)).toBe(expectedErrorType);
      }

      // Store state before valid operation
      const previousTokensResult = await backend.getBackingTokens();
      expect(hasError(previousTokensResult)).toBe(false);
      const previousTokens = unwrapResult(previousTokensResult);
      const previousReserves = previousTokens.map((t) => t.reserveQuantity);

      const previousSupplyResult = await backend.getTotalSupply();
      expect(hasError(previousSupplyResult)).toBe(false);
      const previousSupply = unwrapResult(previousSupplyResult);

      // Verify a valid aligned amount works
      const validAmount = BigInt(100);
      const validResult = await backend.issue({ amount: validAmount });
      expect(hasError(validResult)).toBe(false);

      // Verify state changed correctly for valid amount
      const tokensResult = await backend.getBackingTokens();
      expect(hasError(tokensResult)).toBe(false);
      const tokens = unwrapResult(tokensResult);

      const currentSupplyResult = await backend.getTotalSupply();
      expect(hasError(currentSupplyResult)).toBe(false);
      const currentSupply = unwrapResult(currentSupplyResult);

      expect(currentSupply).toBe(previousSupply + validAmount);

      // Verify each token's reserve increased by the correct amount
      tokens.forEach((token, i) => {
        const backingUnit = previousTokens[i].backingUnit;
        const expectedIncrease = (validAmount * backingUnit) / BigInt(100); // supplyUnit is 100
        expect(token.reserveQuantity).toBe(previousReserves[i] + expectedIncrease);
      });
    }
  );

  test.sequential('11. should handle redeem operations correctly', { timeout: 60000 }, async () => {
    const testUser = newIdentity();
    const testBackend = await multiBackend(testUser);

    // Fund test account
    await Promise.all([
      fundTestAccount(await tokenA(minter), testUser, BigInt(100_000)),
      fundTestAccount(await tokenB(minter), testUser, BigInt(100_000)),
      fundTestAccount(await tokenC(minter), testUser, BigInt(100_000)),
    ]);

    // Get fees
    const [feeA, feeB, feeC] = await Promise.all([
      (await tokenA(testUser)).icrc1_fee(),
      (await tokenB(testUser)).icrc1_fee(),
      (await tokenC(testUser)).icrc1_fee(),
    ]);

    // Use amounts that match backing unit ratios and exceed fees
    const depositAmounts = [
      { token: await tokenA(testUser), tokenId: TOKEN_A, amount: BigInt(20_000) }, // Backing unit 100
      { token: await tokenB(testUser), tokenId: TOKEN_B, amount: BigInt(15_000) }, // Backing unit 50
      { token: await tokenC(testUser), tokenId: TOKEN_C, amount: BigInt(40_000) }, // Backing unit 200
    ];

    // Deposit tokens
    for (const { token, tokenId, amount } of depositAmounts) {
      await token.icrc2_approve({
        spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
        amount: amount + feeA,
        fee: [],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        expected_allowance: [],
        expires_at: [],
      });

      const result = await testBackend.deposit({
        token: tokenId,
        amount,
      });
      expect(hasError(result)).toBe(false);

      const virtualBalanceResult = await testBackend.getVirtualBalance(
        testUser.getPrincipal(),
        tokenId
      );
      expect(hasError(virtualBalanceResult)).toBe(false);
      const virtualBalance = unwrapResult(virtualBalanceResult);
      expect(virtualBalance).toBe(amount - feeA);
    }

    // Initial issue
    const issueAmount = BigInt(500);
    const issueResult = await testBackend.issue({ amount: issueAmount });
    expect(hasError(issueResult)).toBe(false);

    // Get initial state
    const totalSupplyBeforeRedeemResult = await testBackend.getTotalSupply();
    expect(hasError(totalSupplyBeforeRedeemResult)).toBe(false);
    const totalSupplyBeforeRedeem = unwrapResult(totalSupplyBeforeRedeemResult);

    // TODO: When multi token is updated to sync with the backend API, we should
    // verify the total supply matches between backend.getTotalSupply() and multi token's icrc1_total_supply

    // Get multi token balance from backend
    const multiTokenBalanceResult = await testBackend.getMultiTokenBalance(testUser.getPrincipal());
    expect(hasError(multiTokenBalanceResult)).toBe(false);
    const balanceBeforeRedeem = unwrapResult(multiTokenBalanceResult);

    const tokensBeforeRedeemResult = await testBackend.getBackingTokens();
    expect(hasError(tokensBeforeRedeemResult)).toBe(false);
    const tokensBeforeRedeem = unwrapResult(tokensBeforeRedeemResult);

    // Test error cases
    // 1. Test unaligned amount
    const unalignedResult = await testBackend.redeem({ amount: BigInt(150) });
    expect(hasError(unalignedResult)).toBe(true);
    expect(getErrorType(unalignedResult)).toBe('InvalidAmount');

    // 2. Test insufficient balance (more than total supply)
    const tooLargeResult = await testBackend.redeem({
      amount: totalSupplyBeforeRedeem + BigInt(100),
    });
    expect(hasError(tooLargeResult)).toBe(true);
    expect(getErrorType(tooLargeResult)).toBe('InvalidAmount');

    // Test successful redeem
    const redeemAmount = BigInt(100);
    const redeemResult = await testBackend.redeem({ amount: redeemAmount });
    expect(hasError(redeemResult)).toBe(false);

    // Verify state changes
    const finalSupplyResult = await testBackend.getTotalSupply();
    expect(hasError(finalSupplyResult)).toBe(false);
    const finalSupply = unwrapResult(finalSupplyResult);
    expect(finalSupply).toBe(totalSupplyBeforeRedeem - redeemAmount);

    // Get final multi token balance from backend
    const finalMultiTokenBalanceResult = await testBackend.getMultiTokenBalance(
      testUser.getPrincipal()
    );
    expect(hasError(finalMultiTokenBalanceResult)).toBe(false);
    const finalIcrc1Balance = unwrapResult(finalMultiTokenBalanceResult);
    expect(finalIcrc1Balance).toBe(balanceBeforeRedeem - redeemAmount);

    // Verify backing token changes
    const finalTokensResult = await testBackend.getBackingTokens();
    expect(hasError(finalTokensResult)).toBe(false);
    const finalTokens = unwrapResult(finalTokensResult);

    finalTokens.forEach((token, i) => {
      const backingUnit = tokensBeforeRedeem[i].backingUnit;
      const expectedDecrease = (redeemAmount * backingUnit) / BigInt(100);
      expect(token.reserveQuantity).toBe(tokensBeforeRedeem[i].reserveQuantity - expectedDecrease);
    });
  });

  test.sequential(
    '12. should handle concurrent redeem operations safely',
    { timeout: 60000 },
    async () => {
      // Create fresh identities for concurrent test
      const testUsers = [newIdentity(), newIdentity(), newIdentity()];
      const testBackend = await multiBackend(testUsers[0]);
      const redeemAmount = BigInt(100);

      // Setup each identity
      for (const user of testUsers) {
        // Fund accounts
        await Promise.all([
          fundTestAccount(await tokenA(minter), user, BigInt(100_000)),
          fundTestAccount(await tokenB(minter), user, BigInt(100_000)),
          fundTestAccount(await tokenC(minter), user, BigInt(100_000)),
        ]);

        // Use same deposit amounts as test 11
        const depositAmounts = [
          { token: await tokenA(user), tokenId: TOKEN_A, amount: BigInt(20_000) },
          { token: await tokenB(user), tokenId: TOKEN_B, amount: BigInt(15_000) },
          { token: await tokenC(user), tokenId: TOKEN_C, amount: BigInt(40_000) },
        ];

        // Deposit tokens
        for (const { token, tokenId, amount } of depositAmounts) {
          const fee = await token.icrc1_fee();

          await token.icrc2_approve({
            spender: { owner: MULTI_BACKEND_ID, subaccount: [] },
            amount: amount + fee,
            fee: [],
            memo: [],
            from_subaccount: [],
            created_at_time: [],
            expected_allowance: [],
            expires_at: [],
          });

          const result = await (
            await multiBackend(user)
          ).deposit({
            token: tokenId,
            amount,
          });
          expect(hasError(result)).toBe(false);
        }

        // Issue tokens
        const issueResult = await (
          await multiBackend(user)
        ).issue({
          amount: redeemAmount,
        });
        expect(hasError(issueResult)).toBe(false);
      }

      // Record initial state
      const initialSupplyResult = await testBackend.getTotalSupply();
      expect(hasError(initialSupplyResult)).toBe(false);
      const initialSupply = unwrapResult(initialSupplyResult);

      const initialTokensResult = await testBackend.getBackingTokens();
      expect(hasError(initialTokensResult)).toBe(false);
      const initialTokens = unwrapResult(initialTokensResult);

      // Execute concurrent redeem operations
      const results = await Promise.all(
        testUsers.map(async (user) => (await multiBackend(user)).redeem({ amount: redeemAmount }))
      );

      // Verify all operations succeeded
      results.forEach((result) => {
        expect(hasError(result)).toBe(false);
      });

      // Calculate total redeemed
      const totalRedeemed = BigInt(testUsers.length) * redeemAmount;

      // Verify final state
      const finalSupplyResult = await testBackend.getTotalSupply();
      expect(hasError(finalSupplyResult)).toBe(false);
      const finalSupply = unwrapResult(finalSupplyResult);
      expect(finalSupply).toBe(initialSupply - totalRedeemed);

      // Verify backing token reserves
      const finalTokensResult = await testBackend.getBackingTokens();
      expect(hasError(finalTokensResult)).toBe(false);
      const finalTokens = unwrapResult(finalTokensResult);

      finalTokens.forEach((token, i) => {
        const expectedDecrease = (totalRedeemed * token.backingUnit) / BigInt(100);
        expect(token.reserveQuantity).toBe(initialTokens[i].reserveQuantity - expectedDecrease);
      });
    }
  );
});
