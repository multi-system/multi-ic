import React, { useState, useEffect } from 'react';
import { Principal } from '@dfinity/principal';
import { Actor, HttpAgent } from '@dfinity/agent';
import { AuthClient } from '@dfinity/auth-client';
// @ts-ignore
import { idlFactory as backendIdl } from '../../declarations/multi_backend';
// @ts-ignore
import { idlFactory as tokenIdl } from '../../declarations/token_a';
// @ts-ignore
import type { _SERVICE as BackendService } from '../../declarations/multi_backend';
// @ts-ignore
import type { _SERVICE as TokenService } from '../../declarations/token_a';
import { useAuth } from '../contexts/AuthContext';
import { getTokenInfo } from '../config/tokenPrices';
import { showError, logError, safeStringify } from '../utils/errorHandler';

interface TokenBalance {
  canisterId: string;
  name: string;
  symbol: string;
  walletBalance: bigint;
  systemBalance: bigint;
  decimals: number;
}

interface WalletSidebarProps {
  isOpen: boolean;
  onClose: () => void;
}

const WalletSidebar: React.FC<WalletSidebarProps> = ({ isOpen, onClose }) => {
  const { principal } = useAuth();
  const [tokenBalances, setTokenBalances] = useState<TokenBalance[]>([]);
  const [loading, setLoading] = useState(true);
  const [processing, setProcessing] = useState(false);
  const [multiBalance, setMultiBalance] = useState<bigint>(BigInt(0));
  
  // Form states - one deposit amount per token
  const [depositAmounts, setDepositAmounts] = useState<Record<string, string>>({});
  const [issueAmount, setIssueAmount] = useState<string>('');
  const [redeemAmount, setRedeemAmount] = useState<string>('');
  
  // Track which token is being deposited
  const [depositingToken, setDepositingToken] = useState<string | null>(null);

  // Get actors with authenticated identity
  const getAuthenticatedActor = async <T,>(
    idlFactory: any,
    canisterId: string
  ): Promise<T> => {
    const authClient = await AuthClient.create();
    const identity = authClient.getIdentity();
    
    const host = import.meta.env.VITE_DFX_NETWORK === "ic" 
      ? "https://icp-api.io" 
      : "http://localhost:4943";
    
    const agent = new HttpAgent({ 
      host,
      identity 
    });
    
    if (import.meta.env.VITE_DFX_NETWORK !== "ic") {
      await agent.fetchRootKey();
    }

    return Actor.createActor<T>(idlFactory, {
      agent,
      canisterId,
    });
  };

  // Fetch all balances
  const fetchBalances = async () => {
    if (!principal) return;
    
    setLoading(true);
    try {
      const backend = await getAuthenticatedActor<BackendService>(
        backendIdl,
        import.meta.env.VITE_CANISTER_ID_MULTI_BACKEND
      );
      
      // Get system info to know which tokens we're dealing with
      const systemInfoResult = await backend.getSystemInfo();
      if ('err' in systemInfoResult) {
        logError('Failed to get system info', systemInfoResult.err);
        return;
      }
      
      const systemInfo = systemInfoResult.ok;
      
      // Get MULTI token balance
      const multiBalanceResult = await backend.getMultiTokenBalance(principal);
      if ('ok' in multiBalanceResult) {
        setMultiBalance(multiBalanceResult.ok);
      }
      
      // Fetch balances for each backing token
      const balances: TokenBalance[] = [];
      
      for (const backing of systemInfo.backingTokens) {
        const canisterId = backing.tokenInfo.canisterId.toString();
        const tokenActor = await getAuthenticatedActor<TokenService>(tokenIdl, canisterId);
        const tokenInfo = getTokenInfo(canisterId) || {
          name: 'Unknown Token',
          symbol: 'TKN',
          decimals: 8,
        };
        
        // Get wallet balance
        const walletBalance = await tokenActor.icrc1_balance_of({
          owner: principal,
          subaccount: [],
        });
        
        // Get system balance (virtual balance)
        const systemBalanceResult = await backend.getVirtualBalance(principal, backing.tokenInfo.canisterId);
        const systemBalance = 'ok' in systemBalanceResult ? systemBalanceResult.ok : BigInt(0);
        
        balances.push({
          canisterId,
          name: tokenInfo.name,
          symbol: tokenInfo.symbol,
          walletBalance,
          systemBalance,
          decimals: tokenInfo.decimals,
        });
      }
      
      setTokenBalances(balances);
    } catch (error) {
      console.error('Error fetching balances:', error);
    } finally {
      setLoading(false);
    }
  };

  // Refresh balances when sidebar opens or principal changes
  useEffect(() => {
    if (isOpen && principal) {
      fetchBalances();
    }
  }, [isOpen, principal]);

  // Format balance for display
  const formatBalance = (balance: bigint, decimals: number): string => {
    const divisor = BigInt(10 ** decimals);
    const whole = balance / divisor;
    const remainder = balance % divisor;
    
    if (remainder === 0n) {
      return whole.toString();
    }
    
    const decimal = remainder.toString().padStart(decimals, '0').slice(0, 4);
    return `${whole}.${decimal}`;
  };

  // Handle deposit for a specific token
  const handleDeposit = async (tokenCanisterId: string) => {
    const amount = depositAmounts[tokenCanisterId];
    if (!amount || !principal) return;
    
    setDepositingToken(tokenCanisterId);
    try {
      const backend = await getAuthenticatedActor<BackendService>(
        backendIdl,
        import.meta.env.VITE_CANISTER_ID_MULTI_BACKEND
      );
      const tokenActor = await getAuthenticatedActor<TokenService>(
        tokenIdl,
        tokenCanisterId
      );
      
      // Parse and validate the amount
      const parsedAmount = parseFloat(amount);
      if (isNaN(parsedAmount) || parsedAmount <= 0) {
        throw new Error('Invalid amount');
      }
      
      // Convert to smallest unit (8 decimals) - ensure proper BigInt
      const amountInSmallestUnit = Math.floor(parsedAmount * 100000000);
      const depositAmount = BigInt(amountInSmallestUnit);
      const fee = BigInt(10000);
      
      console.log('Deposit details:', {
        amount: depositAmount.toString(),
        token: tokenCanisterId,
        parsedAmount,
        amountInSmallestUnit
      });
      
      // First approve the backend to spend tokens
      const backendPrincipal = Principal.fromText(import.meta.env.VITE_CANISTER_ID_MULTI_BACKEND);
      
      const approveResult = await tokenActor.icrc2_approve({
        spender: { owner: backendPrincipal, subaccount: [] },
        amount: depositAmount + fee,
        fee: [],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        expected_allowance: [],
        expires_at: [],
      });
      
      if ('Err' in approveResult) {
        logError('Token approval failed', approveResult.Err);
        throw new Error(`Approval failed`);
      }
      
      console.log('Approval successful, now depositing...');
      
      // Then deposit
      const tokenPrincipal = Principal.fromText(tokenCanisterId);
      const depositResult = await backend.deposit({
        token: tokenPrincipal,
        amount: depositAmount,
      });
      
      if ('ok' in depositResult) {
        // Clear the input for this token
        setDepositAmounts(prev => ({ ...prev, [tokenCanisterId]: '' }));
        await fetchBalances();
      } else {
        showError('Deposit failed', depositResult.err);
        return;
      }
    } catch (error) {
      console.error('Deposit error:', error);
      if (error instanceof Error) {
        alert(error.message);
      } else {
        alert('Deposit failed: Unknown error');
      }
    } finally {
      setDepositingToken(null);
    }
  };

  // Handle issue
  const handleIssue = async () => {
    if (!issueAmount || !principal) return;
    
    setProcessing(true);
    try {
      const backend = await getAuthenticatedActor<BackendService>(
        backendIdl,
        import.meta.env.VITE_CANISTER_ID_MULTI_BACKEND
      );
      
      const parsedAmount = parseFloat(issueAmount);
      if (isNaN(parsedAmount) || parsedAmount <= 0) {
        throw new Error('Invalid amount');
      }
      
      const amount = BigInt(Math.floor(parsedAmount * 100000000));
      
      const result = await backend.issue({ amount });
      
      if ('ok' in result) {
        setIssueAmount('');
        await fetchBalances();
      } else {
        showError('Issue failed', result.err);
      }
    } catch (error) {
      console.error('Issue error:', error);
      if (error instanceof Error) {
        alert(error.message);
      } else {
        alert('Issue failed: Unknown error');
      }
    } finally {
      setProcessing(false);
    }
  };

  // Handle redeem
  const handleRedeem = async () => {
    if (!redeemAmount || !principal) return;
    
    setProcessing(true);
    try {
      const backend = await getAuthenticatedActor<BackendService>(
        backendIdl,
        import.meta.env.VITE_CANISTER_ID_MULTI_BACKEND
      );
      
      const parsedAmount = parseFloat(redeemAmount);
      if (isNaN(parsedAmount) || parsedAmount <= 0) {
        throw new Error('Invalid amount');
      }
      
      const amount = BigInt(Math.floor(parsedAmount * 100000000));
      
      const result = await backend.redeem({ amount });
      
      if ('ok' in result) {
        setRedeemAmount('');
        await fetchBalances();
      } else {
        showError('Redeem failed', result.err);
      }
    } catch (error) {
      console.error('Redeem error:', error);
      if (error instanceof Error) {
        alert(error.message);
      } else {
        alert('Redeem failed: Unknown error');
      }
    } finally {
      setProcessing(false);
    }
  };

  return (
    <div
      className={`fixed top-0 right-0 h-full w-[28rem] bg-gray-900 shadow-2xl transform transition-transform z-50 overflow-hidden ${
        isOpen ? 'translate-x-0' : 'translate-x-full'
      }`}
    >
      <div className="h-full flex flex-col">
        {/* Header */}
        <div className="p-6 border-b border-gray-800">
          <div className="flex justify-between items-center">
            <h2 className="text-2xl font-bold text-white">Wallet</h2>
            <button
              onClick={onClose}
              className="text-gray-400 hover:text-white transition-colors"
            >
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>
        
        {/* Scrollable Content */}
        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="flex items-center justify-center py-12">
              <div className="text-center text-gray-400">Loading balances...</div>
            </div>
          ) : (
            <div className="p-6 space-y-6">
              {/* MULTI Balance and Operations at the top */}
              <div className="bg-gray-800 rounded-lg p-6 space-y-4">
                <div>
                  <p className="text-sm text-gray-400 mb-1">MULTI Token Balance</p>
                  <p className="text-3xl font-bold text-white">
                    {formatBalance(multiBalance, 8)} MULTI
                  </p>
                </div>
                
                {/* Issue MULTI */}
                <div className="pt-4 border-t border-gray-700">
                  <p className="text-sm font-medium text-gray-300 mb-2">Issue MULTI Tokens</p>
                  <div className="flex gap-2">
                    <input
                      type="number"
                      value={issueAmount}
                      onChange={(e) => setIssueAmount(e.target.value)}
                      placeholder="Amount"
                      className="flex-1 px-3 py-2 bg-gray-700 text-white rounded-lg border border-gray-600 focus:border-[#586CE1] focus:outline-none text-sm"
                    />
                    <button
                      onClick={handleIssue}
                      disabled={processing || !issueAmount}
                      className="px-4 py-2 bg-[#586CE1] hover:bg-[#4056C7] disabled:bg-gray-600 text-white font-medium rounded-lg transition-colors text-sm"
                    >
                      Issue
                    </button>
                  </div>
                </div>
                
                {/* Redeem MULTI */}
                <div>
                  <p className="text-sm font-medium text-gray-300 mb-2">Redeem MULTI Tokens</p>
                  <div className="flex gap-2">
                    <input
                      type="number"
                      value={redeemAmount}
                      onChange={(e) => setRedeemAmount(e.target.value)}
                      placeholder="Amount"
                      className="flex-1 px-3 py-2 bg-gray-700 text-white rounded-lg border border-gray-600 focus:border-[#586CE1] focus:outline-none text-sm"
                    />
                    <button
                      onClick={handleRedeem}
                      disabled={processing || !redeemAmount}
                      className="px-4 py-2 bg-[#586CE1] hover:bg-[#4056C7] disabled:bg-gray-600 text-white font-medium rounded-lg transition-colors text-sm"
                    >
                      Redeem
                    </button>
                  </div>
                  <p className="text-xs text-gray-500 mt-1">
                    Returns backing tokens to your wallet
                  </p>
                </div>
              </div>
              
              {/* Token Portfolio */}
              <div>
                <h3 className="text-lg font-semibold text-white mb-4">Token Portfolio</h3>
                <div className="space-y-4">
                  {tokenBalances.map((token) => (
                    <div key={token.canisterId} className="bg-gray-800 rounded-lg p-5">
                      <div className="mb-3">
                        <h4 className="font-semibold text-white text-lg">
                          {token.name} ({token.symbol})
                        </h4>
                        <p className="text-xs text-gray-500">{token.canisterId}</p>
                      </div>
                      
                      {/* Balances */}
                      <div className="grid grid-cols-2 gap-4 mb-4">
                        <div>
                          <p className="text-xs text-gray-400">Wallet Balance</p>
                          <p className="text-lg font-mono text-white">
                            {formatBalance(token.walletBalance, token.decimals)}
                          </p>
                        </div>
                        <div>
                          <p className="text-xs text-gray-400">Deposited</p>
                          <p className="text-lg font-mono text-white">
                            {formatBalance(token.systemBalance, token.decimals)}
                          </p>
                        </div>
                      </div>
                      
                      {/* Deposit Form */}
                      <div className="pt-3 border-t border-gray-700">
                        <p className="text-sm font-medium text-gray-300 mb-2">Deposit to System</p>
                        <div className="flex gap-2">
                          <input
                            type="number"
                            value={depositAmounts[token.canisterId] || ''}
                            onChange={(e) => setDepositAmounts(prev => ({
                              ...prev,
                              [token.canisterId]: e.target.value
                            }))}
                            placeholder="Amount"
                            className="flex-1 px-3 py-2 bg-gray-700 text-white rounded-lg border border-gray-600 focus:border-[#586CE1] focus:outline-none text-sm"
                          />
                          <button
                            onClick={() => handleDeposit(token.canisterId)}
                            disabled={depositingToken === token.canisterId || !depositAmounts[token.canisterId]}
                            className="px-4 py-2 bg-[#586CE1] hover:bg-[#4056C7] disabled:bg-gray-600 text-white font-medium rounded-lg transition-colors text-sm"
                          >
                            {depositingToken === token.canisterId ? 'Processing...' : 'Deposit'}
                          </button>
                        </div>
                        {token.walletBalance === 0n && (
                          <p className="text-xs text-yellow-400 mt-2">
                            Need tokens? Run: yarn fund {principal?.toText()}
                          </p>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default WalletSidebar;