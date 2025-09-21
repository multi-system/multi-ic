import React, { useState, useEffect, Dispatch, SetStateAction } from "react";
import { Principal } from "@dfinity/principal";
import { Actor, HttpAgent } from "@dfinity/agent";
import { AuthClient } from "@dfinity/auth-client";
import { useSystemInfo } from "../contexts/SystemInfoContext";
// @ts-ignore
import { idlFactory as backendIdl } from "../../declarations/multi_backend";
// @ts-ignore
import { idlFactory as tokenIdl } from "../../declarations/token_a";
// @ts-ignore
import { idlFactory as historyIdl } from "../../declarations/multi_history";
// @ts-ignore
import type { _SERVICE as BackendService } from "../../declarations/multi_backend";
// @ts-ignore
import type { _SERVICE as TokenService } from "../../declarations/token_a";
import { useAuth } from "../contexts/AuthContext";
import { getTokenInfo } from "../config/tokenPrices";
import { getTokenIcon } from "../utils/tokenIcons";
import { showError, logError, safeStringify } from "../utils/errorHandler";
import { TokenBalance } from "../utils/types";
import { Loader } from "./Loader";
import CopyText from "./CopyText";
import Aurora from "./Aurora";
import Tooltip from "./Tooltip";
import {
  FontAwesomeIcon,
  FontAwesomeIconProps,
} from "@fortawesome/react-fontawesome";
import {
  faArrowRightFromBracket,
  faArrowRightToBracket,
  faChevronLeft,
  faEllipsis,
  faMinus,
  faPlus,
  faRightFromBracket,
  faRightToBracket,
  faXmark,
} from "@fortawesome/free-solid-svg-icons";
import DropdownMenu from "./Dropdown";
import { twMerge } from "tailwind-merge";
import Select from "./Select";

type WalletSidebarProps = {
  isOpen: boolean;
  onClose: () => void;
};

type Page = "main" | "deposit" | "withdraw" | "issue" | "redeem";

// Define a shared Asset type that matches both TokenBalance and what the Deposit/Withdraw pages expect
type Asset = {
  canisterId: string;
  name: string;
  symbol: string;
  decimals: number;
  walletBalance?: bigint;
  systemBalance?: bigint;
};

const WalletSidebar: React.FC<WalletSidebarProps> = ({ isOpen, onClose }) => {
  const { principal } = useAuth();
  const [tokenBalances, setTokenBalances] = useState<TokenBalance[]>([]);
  const [loading, setLoading] = useState(true);
  const [processing, setProcessing] = useState(false);
  const [multiBalance, setMultiBalance] = useState<bigint>(BigInt(0));
  const [currentPage, setCurrentPage] = useState<Page>("main");
  const [selectedAsset, setSelectedAsset] = useState<TokenBalance | null>(null);
  const [prices, setPrices] = useState<Record<string, number>>({});

  // Form states - one deposit amount per token
  const [depositAmounts, setDepositAmounts] = useState<Record<string, string>>(
    {},
  );
  const [issueAmount, setIssueAmount] = useState<string>("");

  const { systemInfo } = useSystemInfo();


  // Track which token is being deposited
  const [depositingToken, setDepositingToken] = useState<string | null>(null);

  // Get actors with authenticated identity
  const getAuthenticatedActor = async <T,>(
    idlFactory: any,
    canisterId: string,
  ): Promise<T> => {
    const authClient = await AuthClient.create();
    const identity = authClient.getIdentity();

    const host =
      import.meta.env.VITE_DFX_NETWORK === "ic"
        ? "https://icp-api.io"
        : "http://localhost:4943";

    const agent = new HttpAgent({
      host,
      identity,
    });

    if (import.meta.env.VITE_DFX_NETWORK !== "ic") {
      await agent.fetchRootKey();
    }

    return Actor.createActor<T>(idlFactory, {
      agent,
      canisterId,
    });
  };

  // Fetch current prices from history canister
  const fetchCurrentPrices = async () => {
    try {
      const historyActor = await getAuthenticatedActor(
        historyIdl,
        import.meta.env.VITE_CANISTER_ID_MULTI_HISTORY,
      );

      // Get latest snapshot
      const latestSnapshots = await historyActor.getSnapshotsInTimeRange(
        BigInt(Date.now()) * BigInt(1000000) - BigInt(3600 * 1000000000), // Last hour
        BigInt(Date.now()) * BigInt(1000000),
        [1] // Just get the latest one
      );

      if (latestSnapshots.length > 0) {
        const snapshot = latestSnapshots[0].snapshot;
        const newPrices: Record<string, number> = {};

        snapshot.prices.forEach(([token, price]: [any, bigint]) => {
          newPrices[token.toString()] = Number(price) / 100000000; // Convert to USD
        });

        setPrices(newPrices);
      }
    } catch (error) {
      console.error('Error fetching prices:', error);
    }
  };

  // Fetch all balances
  const fetchBalances = async () => {
    if (!principal) return;

    setLoading(true);
    try {
      const backend = await getAuthenticatedActor<BackendService>(
        backendIdl,
        import.meta.env.VITE_CANISTER_ID_MULTI_BACKEND,
      );

      // Get system info to know which tokens we're dealing with
      const systemInfoResult = await backend.getSystemInfo();
      if ("err" in systemInfoResult) {
        logError("Failed to get system info", systemInfoResult.err);
        return;
      }

      const systemInfo = systemInfoResult.ok;

      // Get MULTI token balance
      const multiBalanceResult = await backend.getMultiTokenBalance(principal);
      if ("ok" in multiBalanceResult) {
        setMultiBalance(multiBalanceResult.ok);
      }

      // Fetch balances for each backing token
      const balances: TokenBalance[] = [];

      for (const backing of systemInfo.backingTokens) {
        const canisterId = backing.tokenInfo.canisterId.toString();
        const tokenActor = await getAuthenticatedActor<TokenService>(
          tokenIdl,
          canisterId,
        );
        const tokenInfo = getTokenInfo(canisterId) || {
          name: "Unknown Token",
          symbol: "TKN",
          decimals: 8,
        };

        // Get wallet balance
        const walletBalance = await tokenActor.icrc1_balance_of({
          owner: principal,
          subaccount: [],
        });

        // Get system balance (virtual balance)
        const systemBalanceResult = await backend.getVirtualBalance(
          principal,
          backing.tokenInfo.canisterId,
        );
        const systemBalance =
          "ok" in systemBalanceResult ? systemBalanceResult.ok : BigInt(0);

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
      console.error("Error fetching balances:", error);
    } finally {
      setLoading(false);
    }
  };

  // Refresh balances and prices when sidebar opens or principal changes
  useEffect(() => {
    if (isOpen && principal) {
      Promise.all([
        fetchBalances(),
        fetchCurrentPrices()
      ]);
    }
  }, [isOpen, principal]);

  // Handle deposit for a specific token
  const handleDeposit = async (asset: Asset, amount: string) => {
    if (!amount || !principal) return;

    const tokenCanisterId = asset.canisterId;
    setDepositingToken(tokenCanisterId);
    try {
      const backend = await getAuthenticatedActor<BackendService>(
        backendIdl,
        import.meta.env.VITE_CANISTER_ID_MULTI_BACKEND,
      );
      const tokenActor = await getAuthenticatedActor<TokenService>(
        tokenIdl,
        tokenCanisterId,
      );

      // Parse and validate the amount
      const parsedAmount = formatStringToBigInt(amount, asset.decimals);
      if (parsedAmount === null || parsedAmount <= 0n) {
        throw new Error("Invalid amount");
      }

      const depositAmount = parsedAmount;

      console.log("Deposit details:", {
        amount: depositAmount.toString(),
        token: tokenCanisterId,
        parsedAmount,
      });

      // First approve the backend to spend tokens
      const backendPrincipal = Principal.fromText(
        import.meta.env.VITE_CANISTER_ID_MULTI_BACKEND,
      );

      const approveResult = await tokenActor.icrc2_approve({
        spender: { owner: backendPrincipal, subaccount: [] },
        amount: depositAmount + BigInt(10000), // Add a small buffer for fees
        fee: [],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        expected_allowance: [],
        expires_at: [],
      });

      if ("Err" in approveResult) {
        logError("Token approval failed", approveResult.Err);
        throw new Error(`Approval failed`);
      }

      console.log("Approval successful, now depositing...");

      // Then deposit
      const tokenPrincipal = Principal.fromText(tokenCanisterId);
      const depositResult = await backend.deposit({
        token: tokenPrincipal,
        amount: depositAmount,
      });

      if ("ok" in depositResult) {
        // Clear the input for this token
        setDepositAmounts((prev) => ({ ...prev, [tokenCanisterId]: "" }));
        await fetchBalances();
      } else {
        showError("Deposit failed", depositResult.err);
        return;
      }
    } catch (error) {
      console.error("Deposit error:", error);
      if (error instanceof Error) {
        alert(error.message);
      } else {
        alert("Deposit failed: Unknown error");
      }
    } finally {
      setDepositingToken(null);
      fetchBalances();
    }
  };

  // Handle withdraw for a specific token
  const handleWithdraw = async (asset: Asset, amount: string) => {
    if (!amount || !principal) return;

    const tokenCanisterId = asset.canisterId;
    setDepositingToken(tokenCanisterId); // Reuse this state for withdrawing
    try {
      const backend = await getAuthenticatedActor<BackendService>(
        backendIdl,
        import.meta.env.VITE_CANISTER_ID_MULTI_BACKEND,
      );

      // Parse and validate the amount
      const parsedAmount = formatStringToBigInt(amount, asset.decimals);
      if (parsedAmount === null || parsedAmount <= 0n) {
        throw new Error("Invalid amount");
      }

      console.log("Withdraw details:", {
        amount: parsedAmount.toString(),
        token: tokenCanisterId,
      });

      // Call withdraw on the backend
      const tokenPrincipal = Principal.fromText(tokenCanisterId);
      const withdrawResult = await backend.withdraw({
        token: tokenPrincipal,
        amount: parsedAmount,
      });

      if ("ok" in withdrawResult) {
        console.log("Withdraw successful");
        await fetchBalances();
      } else {
        console.error("Withdraw failed:", withdrawResult.err);
        showError("Withdraw failed", withdrawResult.err);
      }
    } catch (error) {
      console.error("Withdraw error:", error);
      if (error instanceof Error) {
        alert(error.message);
      } else {
        alert("Withdraw failed: Unknown error");
      }
    } finally {
      setDepositingToken(null);
      fetchBalances();
    }
  };

  // Handle issue
  const handleIssue = async (amount: string) => {
    if (!amount || !principal) return;

    setProcessing(true);
    try {
      const backend = await getAuthenticatedActor<BackendService>(
        backendIdl,
        import.meta.env.VITE_CANISTER_ID_MULTI_BACKEND,
      );

      const parsedAmount = formatStringToBigInt(amount, 8);
      if (parsedAmount === null || parsedAmount <= 0n) {
        throw new Error("Invalid amount");
      }

      const result = await backend.issue({ amount: parsedAmount });

      if ("ok" in result) {
        setIssueAmount("");
        await fetchBalances();
      } else {
        showError("Issue failed", result.err);
      }
    } catch (error) {
      console.error("Issue error:", error);
      if (error instanceof Error) {
        alert(error.message);
      } else {
        alert("Issue failed: Unknown error");
      }
    } finally {
      setProcessing(false);
    }
  };

  // Handle redeem
  const handleRedeem = async (amount: string) => {
    if (!amount || !principal) return;

    setProcessing(true);
    try {
      const backend = await getAuthenticatedActor<BackendService>(
        backendIdl,
        import.meta.env.VITE_CANISTER_ID_MULTI_BACKEND,
      );

      const parsedAmount = formatStringToBigInt(amount, 8);
      if (parsedAmount === null || parsedAmount <= 0n) {
        throw new Error("Invalid amount");
      }

      const result = await backend.redeem({ amount: parsedAmount });

      if ("ok" in result) {
        await fetchBalances();
      } else {
        showError("Redeem failed", result.err);
      }
    } catch (error) {
      console.error("Redeem error:", error);
      if (error instanceof Error) {
        alert(error.message);
      } else {
        alert("Redeem failed: Unknown error");
      }
    } finally {
      setProcessing(false);
    }
  };

  // Close sidebar on Escape key
  useEffect(() => {
    if (!isOpen) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        onClose();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, onClose]);

  return (
    <>
      {isOpen && (
        <div
          className="w-full min-h-screen top-0 left-0 fixed bg-black/40 z-40"
          onClick={onClose}
        />
      )}

      <div
        className={`fixed top-0 right-0 h-full w-[28rem] bg-gray-900 shadow-2xl transform transition-transform z-50 overflow-hidden overflow-y-auto ${isOpen ? "translate-x-0" : "translate-x-full"
          }`}
      >
        {currentPage === "deposit" && (
          <DepositPage
            loading={depositingToken !== null}
            onBack={() => setCurrentPage("main")}
            preSelectedAsset={selectedAsset as Asset}
            assets={tokenBalances}
            onDeposit={async (asset: Asset, amount: string) => {
              await handleDeposit(asset, amount);
              await fetchBalances(); // Make sure balances are updated
            }}
          />
        )}

        {currentPage === "withdraw" && (
          <WithdrawPage
            loading={depositingToken !== null}
            onBack={() => setCurrentPage("main")}
            preSelectedAsset={selectedAsset as Asset}
            assets={tokenBalances}
            onWithdraw={handleWithdraw}
          />
        )}

        {currentPage === "issue" && (
          <IssuePage
            loading={processing}
            onBack={() => setCurrentPage("main")}
            assets={tokenBalances}
            onIssue={async (amount: string) => {
              await handleIssue(amount);
              await fetchBalances();
            }}
          />
        )}

        {currentPage === "redeem" && (
          <RedeemPage
            loading={processing}
            onBack={() => setCurrentPage("main")}
            assets={tokenBalances}
            onRedeem={async (amount: string) => {
              await handleRedeem(amount);
              await fetchBalances();
            }}
            multiBalance={multiBalance}
          />
        )}

        {currentPage === "main" && (
          <MainPage
            onClose={onClose}
            multiBalance={multiBalance}
            setCurrentPage={setCurrentPage}
            loading={loading}
            tokenBalances={tokenBalances}
            setSelectedAsset={setSelectedAsset}
            principal={principal}
            prices={prices}
          />
        )}
      </div>
    </>
  );
};

function TopButton({
  label,
  disabled = false,
  tip,
  onClick,
  icon,
}: {
  disabled?: boolean;
  label: string;
  tip: string;
  onClick: () => void;
  icon: FontAwesomeIconProps["icon"];
}) {
  return (
    <Tooltip tip={tip}>
      <button
        onClick={onClick}
        disabled={disabled}
        className={`flex group items-center flex-col gap-2 w-12 ${disabled ? "cursor-not-allowed opacity-50" : ""
          }`}
      >
        <FontAwesomeIcon
          icon={icon}
          className={`text-base p-3 rounded-full ${disabled
            ? "bg-white/10"
            : "bg-white/20 group-hover:bg-white/30"
            }`}
        />
        <span className={`text-xs font-base ${disabled
          ? "text-white/40"
          : "text-white/60 group-hover:text-white/80"
          }`}>
          {label}
        </span>
      </button>
    </Tooltip>
  );
}


function MainPage({
  onClose,
  multiBalance,
  setCurrentPage,
  loading,
  tokenBalances,
  setSelectedAsset,
  principal,
  prices,
}: {
  onClose: () => void;
  multiBalance: bigint;
  setCurrentPage: Dispatch<SetStateAction<Page>>;
  loading: boolean;
  tokenBalances: TokenBalance[];
  setSelectedAsset: (asset: TokenBalance | null) => void;
  principal: Principal | null;
  prices: Record<string, number>;
}) {
  // Calculate total value in USD
  const calculateTotalValue = () => {
    let total = 0;

    // Add value of MULTI tokens
    const multiPrice = prices[import.meta.env.VITE_CANISTER_ID_MULTI_BACKEND] || 1; // Default to 1 USD if no price
    total += Number(multiBalance) * multiPrice / 100000000; // Convert from e8s

    // Add value of backing tokens
    tokenBalances.forEach(token => {
      const price = prices[token.canisterId] || 1; // Default to 1 USD if no price
      if (token.systemBalance) {
        total += Number(token.systemBalance) * price / (10 ** token.decimals);
      }
    });

    return total;
  };
  return (
    <div className="flex flex-col">
      <Aurora className="w-full h-92 items-center ">
        <div
          className="absolute h-92 inset-0 w-full h-full pointer-events-none z-0"
          style={{
            background:
              "linear-gradient(to bottom, rgba(4, 0, 20, 0.85) 0%, rgba(0, 18, 56, 0.6) 40%, rgba(75, 0, 59, 0.2) 80%, rgba(19, 0, 63, 0) 100%)",
          }}
        />
        <div className="p-6 pt-4 z-10 relative flex flex-col gap-4 items-center">
          <div className="flex justify-end w-full items-center">
            <button
              onClick={onClose}
              className="text-gray-400 hover:text-white transition-colors"
            >
              <FontAwesomeIcon icon={faXmark} />
            </button>
          </div>

          <div className="text-center mt-16 items-center flex flex-col gap-2 justify-center w-full">
            <div className="flex flex-col items-center justify-center gap-2">
              <p className="text-sm font-thin text-white/60">
                Total Deposited Value
              </p>
              <div className="flex items-end flex-row gap-1">
                <p className="text-5xl font-mono font-bold text-white">
                  ${calculateTotalValue().toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                </p>
              </div>
              <div className="flex items-center gap-2 bg-black/50 px-4 py-2 rounded-full">
                <p className="text-sm font-thin text-white/40">MULTI Balance:</p>
                <p className="text-sm font-mono font-black text-white/80">
                  {formatBalance(multiBalance, 8)} <span className="font-thin text-white/40">MULTI</span>
                </p>
              </div>
            </div>
          </div>

          <div className="flex flex-row  mt-8 gap-4 items-center justify-center w-full px-8">
            <TopButton
              key="issue"
              label="Issue"
              tip="Create new MULTI tokens from your deposited assets"
              onClick={() => setCurrentPage("issue")}
              icon={faPlus}
            />
            <TopButton
              key="redeem"
              label="Redeem"
              tip="Destroy MULTI tokens to recieve the underlying assets"
              onClick={() => setCurrentPage("redeem")}
              icon={faMinus}
            />
            <div className="w-px h-10 -mt-6 bg-white/30" />
            <TopButton
              key={"deposit"}
              label="Deposit"
              tip="Add assets to the Multi virtual wallet"
              onClick={() => setCurrentPage("deposit")}
              icon={faRightToBracket}
            />
            <TopButton
              key="withdraw"
              label="Withdraw"
              tip="Remove assets from the Multi virtual wallet"
              onClick={() => setCurrentPage("withdraw")}
              icon={faRightFromBracket}
            />
          </div>
        </div>
      </Aurora>

      {/* Scrollable Content */}
      <div className="flex-1 w-full flex pb-4">
        {loading ? (
          <div className="w-full mt-12 text-center my-auto items-center justify-center  text-gray-400 flex">
            <Loader size="lg" />
          </div>
        ) : (
          <div className="px-4 space-y-6 w-full">
            {/* MULTI Balance and Operations at the top */}
            <div className="rounded-lg space-y-4">
              {/* Issue MULTI 
                  <div className="pt-4 border-t border-gray-700">
                    <p className="text-sm font-medium text-gray-300 mb-2">Issue MULTI Tokens</p>
                    <div className="flex gap-2">
                      <IncrementalInput
                        value={issueAmount}
                        onChange={(e) => setIssueAmount(e.target.value)}
                        placeholder="Amount"
                      />
                      <button
                        onClick={handleIssue}
                        disabled={processing || Number(issueAmount) === 0}
                        className="px-4 py-2 bg-[#586CE1] hover:bg-[#4056C7] disabled:bg-gray-600 text-white font-medium rounded-lg transition-colors text-sm"
                      >
                        Issue
                      </button>
                    </div>
                  </div>


                  <div>
                    <p className="text-sm font-medium text-gray-300 mb-2">Redeem MULTI Tokens</p>
                    <div className="flex gap-2">
                      <IncrementalInput
                        value={redeemAmount}
                        onChange={(e) => setRedeemAmount(e.target.value)}
                        placeholder="Amount"
                      />
                      <button
                        onClick={handleRedeem}
                        disabled={processing || Number(redeemAmount) === 0}
                        className="px-4 py-2 bg-[#586CE1] hover:bg-[#4056C7] disabled:bg-gray-600 text-white font-medium rounded-lg transition-colors text-sm"
                      >
                        Redeem
                      </button>
                    </div>
                    <p className="text-xs text-gray-500 mt-1">
                      Returns backing tokens to your wallet
                    </p>
                  </div>
                  */}
            </div>

            {/* Token Portfolio */}

            <div className="space-y-4 w-full">
              {tokenBalances.map((token) => {
                const icon = getTokenIcon(token.symbol);
                return (
                  <div
                    key={token.canisterId}
                    className="bg-gray-800 w-full rounded-lg p-4"
                  >
                    <div className="flex flex-row justify-between">
                      <div className="mb-2 flex flex-row gap-2 items-center">
                        {icon && (
                          <img
                            src={icon}
                            alt={token.symbol}
                            className="w-8 h-8"
                          />
                        )}
                        <div className="flex flex-col leading-none">
                          <h4 className="font-semibold -mb-0.5 text-white">
                            {token.name}{" "}
                            <span className="font-thin text-sm text-white/50">
                              {token.symbol}
                            </span>
                          </h4>
                          <CopyText copyText={token.canisterId}>
                            <p className="text-xs text-gray-500 hover:text-blue-500">
                              {token.canisterId}
                            </p>
                          </CopyText>
                        </div>
                      </div>
                      <DropdownMenu
                        triggerLabel={
                          <button className="text-gray-400 hover:text-white">
                            <FontAwesomeIcon icon={faEllipsis} />
                          </button>
                        }
                        options={[
                          {
                            label: <div className="flex flex-row gap-2 items-center text-white/60">
                              <FontAwesomeIcon icon={faArrowRightToBracket} />
                              <span className="text-white">Deposit</span>
                            </div>,
                            onClick: () => {
                              setSelectedAsset(token);
                              setCurrentPage("deposit");
                            },
                          },
                          {
                            label: <div className="flex flex-row gap-2 items-center text-white/60">
                              <FontAwesomeIcon icon={faArrowRightFromBracket} />
                              <span className="text-white">Withdraw</span>
                            </div>,
                            onClick: () => {
                              setSelectedAsset(token);
                              setCurrentPage("withdraw");
                            },
                          },
                        ]}
                      />
                    </div>
                    <div className=" h-px w-full bg-white/10 mb-2" />
                    {/* Balances */}
                    <div className="grid grid-cols-2 gap-4">
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
                  </div>
                );
              })}
            </div>
            {tokenBalances.some((token) => token.walletBalance === 0n) && (
              <p className="text-xs text-yellow-400 mt-2">
                Need tokens? Run: yarn fund {principal?.toText()}
              </p>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
export default WalletSidebar;


function DepositPage({
  onBack,
  preSelectedAsset,
  assets,
  onDeposit,
  loading,
}: {
  loading: boolean;
  onBack: () => void;
  preSelectedAsset?: Asset;
  assets: Asset[];
  onDeposit: (asset: Asset, amount: string) => Promise<void>;
}) {
  const [selectedAsset, setSelectedAsset] = useState<Asset | null>(
    preSelectedAsset || null
  );
  const [amount, setAmount] = useState("");

  // Update selected asset when assets change or preSelectedAsset changes
  useEffect(() => {
    if (selectedAsset) {
      // Find the updated asset with the same canisterId
      const updatedAsset = assets.find(a => a.canisterId === selectedAsset.canisterId);
      if (updatedAsset) {
        setSelectedAsset(updatedAsset);
      }
    } else if (preSelectedAsset) {
      setSelectedAsset(preSelectedAsset);
    }
  }, [assets, preSelectedAsset]);

  // Clear amount when loading transitions from true to false (transaction complete)
  useEffect(() => {
    if (!loading) {
      setAmount("");
    }
  }, [loading]);

  const handleDeposit = async () => {
    if (!selectedAsset || !amount) return;
    await onDeposit(selectedAsset, amount);
  };

  const bigIntAmount = formatStringToBigInt(amount, selectedAsset?.decimals ?? 0);
  const walletBefore = selectedAsset?.walletBalance ?? 0n;
  const systemBefore = selectedAsset?.systemBalance ?? 0n;
  const walletAfter = walletBefore - (bigIntAmount ?? 0n);
  const tooMuch = bigIntAmount !== null && walletAfter < 0n;


  return (
    <div className="flex flex-col h-full">
      <Aurora className="w-full h-92">
        <div
          className="absolute h-92 inset-0 w-full h-full pointer-events-none z-0"
          style={{
            background:
              "linear-gradient(to bottom, rgba(4, 0, 20, 0.85) 0%, rgba(0, 18, 56, 0.6) 40%, rgba(75, 0, 59, 0.2) 80%, rgba(19, 0, 63, 0) 100%)",
          }}
        />
        <div className="p-6 pt-4 z-10 relative flex flex-col gap-4">
          <div className="flex justify-between w-full items-center">
            <button
              onClick={onBack}
              className="text-gray-400 hover:text-white transition-colors"
            >
              <FontAwesomeIcon icon={faChevronLeft} />
            </button>
            <h2 className="text-base text-white/60">Deposit Assets</h2>
            <div className="w-6" /> {/* Spacer for alignment */}
          </div>

          <div className="mt-8 space-y-6">
            <div className="space-y-2">
              <label className="text-sm text-white/60">Select Asset</label>
              <Select
                selectedValue={selectedAsset?.canisterId || ""}
                onChange={(value) =>
                  setSelectedAsset(
                    assets.find((a) => a.canisterId === value) || null
                  )
                }
                placeholder="Select an asset"
                options={
                  assets.map((asset) => ({
                    value: asset.canisterId,
                    label: <div className="flex items-end flex-row gap-1"><span>{asset.name}</span><span className="text-white/60 font-thin ">{asset.symbol}</span></div>,
                  }))
                }
              />
            </div>

            <div className="space-y-2">
              <label className="text-sm text-white/60">Amount</label>
              <input
                type="number"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="Enter amount"
                className="w-full bg-black/20 border border-white/20 text-white rounded-lg p-3 focus:outline-none focus:border-white/40"
              />
            </div>
          </div>
        </div>
      </Aurora>

      <TransactionPreview selectedAsset={selectedAsset} bigIntAmount={formatStringToBigInt(amount, selectedAsset?.decimals ?? 0) ?? null} />

      <div className="p-6 border-t border-white/10">
        <LargeFullButton
          loading={loading}
          onClick={handleDeposit}
          disabled={!selectedAsset || !amount || bigIntAmount === 0n || tooMuch}
        >
          <span className=""></span>Deposit
        </LargeFullButton>
      </div>
    </div>
  );
}

function WithdrawPage({
  onBack,
  preSelectedAsset,
  assets,
  onWithdraw,
  loading,
}: {
  loading: boolean;
  onBack: () => void;
  preSelectedAsset?: Asset;
  assets: Asset[];
  onWithdraw: (asset: Asset, amount: string) => Promise<void>;
}) {
  const [selectedAsset, setSelectedAsset] = useState<Asset | null>(
    preSelectedAsset || null
  );
  const [amount, setAmount] = useState("");

  // Update selected asset when assets change or preSelectedAsset changes
  useEffect(() => {
    if (selectedAsset) {
      const updatedAsset = assets.find(a => a.canisterId === selectedAsset.canisterId);
      if (updatedAsset) {
        setSelectedAsset(updatedAsset);
      }
    } else if (preSelectedAsset) {
      setSelectedAsset(preSelectedAsset);
    }
  }, [assets, preSelectedAsset]);

  // Clear amount when loading transitions from true to false (transaction complete)
  useEffect(() => {
    if (!loading) {
      setAmount("");
    }
  }, [loading]);

  const handleWithdraw = async () => {
    if (!selectedAsset || !amount) return;
    await onWithdraw(selectedAsset, amount);
  };

  const bigIntAmount = formatStringToBigInt(amount, selectedAsset?.decimals ?? 0);
  const systemBefore = selectedAsset?.systemBalance ?? 0n;
  const walletBefore = selectedAsset?.walletBalance ?? 0n;
  const systemAfter = systemBefore - (bigIntAmount ?? 0n);
  const walletAfter = walletBefore + (bigIntAmount ?? 0n);
  const insufficientBalance = bigIntAmount !== null && systemAfter < 0n;

  return (
    <div className="flex flex-col h-full">
      <Aurora className="w-full h-92">
        <div
          className="absolute h-92 inset-0 w-full h-full pointer-events-none z-0"
          style={{
            background:
              "linear-gradient(to bottom, rgba(4, 0, 20, 0.85) 0%, rgba(0, 18, 56, 0.6) 40%, rgba(75, 0, 59, 0.2) 80%, rgba(19, 0, 63, 0) 100%)",
          }}
        />
        <div className="p-6 pt-4 z-10 relative flex flex-col gap-4">
          <div className="flex justify-between w-full items-center">
            <button
              onClick={onBack}
              className="text-gray-400 hover:text-white transition-colors"
            >
              <FontAwesomeIcon icon={faChevronLeft} />
            </button>
            <h2 className="text-base text-white/60">Withdraw Assets</h2>
            <div className="w-6" />
          </div>

          <div className="mt-8 space-y-6">
            <div className="space-y-2">
              <label className="text-sm text-white/60">Select Asset</label>
              <Select
                selectedValue={selectedAsset?.canisterId || ""}
                onChange={(value) =>
                  setSelectedAsset(
                    assets.find((a) => a.canisterId === value) || null
                  )
                }
                placeholder="Select an asset"
                options={
                  assets.map((asset) => ({
                    value: asset.canisterId,
                    label: <div className="flex items-end flex-row gap-1">
                      <span>{asset.name}</span>
                      <span className="text-white/60 font-thin ">{asset.symbol}</span>
                    </div>,
                  }))
                }
              />
            </div>

            <div className="space-y-2">
              <label className="text-sm text-white/60">Amount to Withdraw</label>
              <input
                type="number"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="Enter amount"
                className="w-full bg-black/20 border border-white/20 text-white rounded-lg p-3 focus:outline-none focus:border-white/40"
              />
            </div>
          </div>
        </div>
      </Aurora>

      {/* Withdraw Preview */}
      <div className="flex-1 p-6">
        <div className="bg-gray-800/50 backdrop-blur rounded-xl p-6 mb-4">
          <div className="flex flex-col gap-6">
            {/* Transaction Type Header */}
            <div className="flex items-center justify-between pb-4 border-b border-white/10">
              <div className="flex items-center gap-3">
                <div className="w-8 h-8 rounded-full bg-[#586CE1]/20 flex items-center justify-center">
                  <FontAwesomeIcon icon={faArrowRightFromBracket} className="text-[#586CE1]" />
                </div>
                <div>
                  <h3 className="text-white font-medium">Withdraw Preview</h3>
                  <p className="text-sm text-white/40">Transaction Details</p>
                </div>
              </div>
            </div>

            {/* Current Balances */}
            <div>
              <p className="text-sm text-white/40 mb-3">Current Balances</p>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-1">
                  <p className="text-xs text-white/60">Deposited Balance</p>
                  <p className="text-lg font-mono text-white">
                    {selectedAsset ? formatBalance(systemBefore, selectedAsset.decimals) : "-"}
                    <span className="text-xs text-white/40 ml-1">{selectedAsset?.symbol}</span>
                  </p>
                </div>
                <div className="space-y-1">
                  <p className="text-xs text-white/60">Wallet Balance</p>
                  <p className="text-lg font-mono text-white">
                    {selectedAsset ? formatBalance(walletBefore, selectedAsset.decimals) : "-"}
                    <span className="text-xs text-white/40 ml-1">{selectedAsset?.symbol}</span>
                  </p>
                </div>
              </div>
            </div>

            {/* Transaction Amount */}
            <div className="py-4 border-y border-white/10">
              <div className="flex justify-between items-center">
                <p className="text-sm text-white/60">Amount to Withdraw</p>
                <p className="text-lg font-mono text-white">
                  {bigIntAmount ? formatBalance(bigIntAmount, selectedAsset?.decimals ?? 0) : "-"}
                  <span className="text-xs text-white/40 ml-1">{selectedAsset?.symbol}</span>
                </p>
              </div>
            </div>

            {/* After Transaction */}
            <div>
              <p className="text-sm text-white/40 mb-3">Expected Balance After</p>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-1">
                  <p className="text-xs text-white/60">Deposited Balance</p>
                  <p className={`text-lg font-mono ${insufficientBalance ? 'text-red-400' : 'text-white'}`}>
                    {selectedAsset ? formatBalance(systemAfter, selectedAsset.decimals) : "-"}
                    <span className="text-xs text-white/40 ml-1">{selectedAsset?.symbol}</span>
                  </p>
                </div>
                <div className="space-y-1">
                  <p className="text-xs text-white/60">Wallet Balance</p>
                  <p className="text-lg font-mono text-white">
                    {selectedAsset ? formatBalance(walletAfter, selectedAsset.decimals) : "-"}
                    <span className="text-xs text-white/40 ml-1">{selectedAsset?.symbol}</span>
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div className="p-6 border-t border-white/10">
        <LargeFullButton
          loading={loading}
          onClick={handleWithdraw}
          disabled={!selectedAsset || !amount || bigIntAmount === 0n || insufficientBalance}
        >
          Withdraw
        </LargeFullButton>
      </div>
    </div>
  );
}

function LargeFullButton({ onClick, disabled, children, loading }: { onClick: () => void; disabled?: boolean; children: React.ReactNode; loading: boolean; }) {
  return (
    <button
      onClick={onClick}
      disabled={disabled || loading}
      className={twMerge("w-full relative bg-[#586CE1] hover:bg-[#4056C7] disabled:bg-gray-800 text-white font-medium rounded-lg p-4 transition-colors",
        disabled ? "cursor-not-allowed text-white/30" : "text-white"
      )}
    >
      {loading ? <div className="absolute inset-0 flex items-center justify-center"><Loader size="md" /></div> : null}
      <div className={loading ? "opacity-0 pointer-events-none" : ""}>
        {children}
      </div>
    </button>
  );
}

function IssuePage({
  onBack,
  assets,
  onIssue,
  loading,
}: {
  loading: boolean;
  onBack: () => void;
  assets: Asset[];
  onIssue: (amount: string) => Promise<void>;
}) {
  const [amount, setAmount] = useState("");

  // Clear amount when loading transitions from true to false (transaction complete)
  useEffect(() => {
    if (!loading) {
      setAmount("");
    }
  }, [loading]);

  const handleIssue = async () => {
    if (!amount) return;
    await onIssue(amount);
  };

  const { systemInfo } = useSystemInfo();
  const issueAmount = formatStringToBigInt(amount, 8); // MULTI token has 8 decimals
  const multiRequired = issueAmount ?? 0n;
  const backingRequired = assets.map(asset => {
    const backingToken = systemInfo?.backingTokens.find(token =>
      token.tokenInfo.canisterId.toString() === asset.canisterId
    );
    const amountPerMulti = backingToken && systemInfo
      ? Number(backingToken.backingUnit) / Number(systemInfo.supplyUnit)
      : 0;
    return {
      ...asset,
      requiredAmount: BigInt(Math.floor(Number(multiRequired) * amountPerMulti * (10 ** asset.decimals) / 100000000))
    };
  });

  const insufficientFunds = backingRequired.some(asset =>
    asset.requiredAmount > (asset.systemBalance ?? 0n)
  );

  return (
    <div className="flex flex-col h-full">
      <Aurora className="w-full h-92">
        <div
          className="absolute h-92 inset-0 w-full h-full pointer-events-none z-0"
          style={{
            background:
              "linear-gradient(to bottom, rgba(4, 0, 20, 0.85) 0%, rgba(0, 18, 56, 0.6) 40%, rgba(75, 0, 59, 0.2) 80%, rgba(19, 0, 63, 0) 100%)",
          }}
        />
        <div className="p-6 pt-4 z-10 relative flex flex-col gap-4">
          <div className="flex justify-between w-full items-center">
            <button
              onClick={onBack}
              className="text-gray-400 hover:text-white transition-colors"
            >
              <FontAwesomeIcon icon={faChevronLeft} />
            </button>
            <h2 className="text-base text-white/60">Issue MULTI</h2>
            <div className="w-6" />
          </div>

          <div className="mt-8 space-y-6">
            <div className="space-y-2">
              <label className="text-sm text-white/60">Amount to Issue</label>
              <input
                type="number"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="Enter amount of MULTI to issue"
                className="w-full bg-black/20 border border-white/20 text-white rounded-lg p-3 focus:outline-none focus:border-white/40"
              />
            </div>
          </div>
        </div>
      </Aurora>

      {/* Issue Preview */}
      <div className="flex-1 p-6">
        <div className="bg-gray-800/50 backdrop-blur rounded-xl p-6 mb-4">
          <div className="flex flex-col gap-6">
            {/* Transaction Type Header */}
            <div className="flex items-center justify-between pb-4 border-b border-white/10">
              <div className="flex items-center gap-3">
                <div className="w-8 h-8 rounded-full bg-[#586CE1]/20 flex items-center justify-center">
                  <FontAwesomeIcon icon={faPlus} className="text-[#586CE1]" />
                </div>
                <div>
                  <h3 className="text-white font-medium">Issue Preview</h3>
                  <p className="text-sm text-white/40">Transaction Details</p>
                </div>
              </div>
            </div>

            {/* Issue Amount */}
            <div className="py-4 border-b border-white/10">
              <div className="flex justify-between items-center">
                <p className="text-sm text-white/60">Amount to Issue</p>
                <p className="text-lg font-mono text-white">
                  {issueAmount ? formatBalance(issueAmount, 8) : "-"}
                  <span className="text-xs text-white/40 ml-1">MULTI</span>
                </p>
              </div>
            </div>

            {/* Required Backing Assets */}
            <div>
              <p className="text-sm text-white/40 mb-3">Required Backing Assets</p>
              <div className="space-y-4">
                {backingRequired.map((asset) => (
                  <div key={asset.canisterId} className="grid grid-cols-2 gap-4">
                    <div className="space-y-1">
                      <p className="text-xs text-white/60">Current Balance</p>
                      <p className="text-lg font-mono text-white">
                        {formatBalance(asset.systemBalance ?? 0n, asset.decimals)}
                        <span className="text-xs text-white/40 ml-1">{asset.symbol}</span>
                      </p>
                    </div>
                    <div className="space-y-1">
                      <p className="text-xs text-white/60">Required Amount</p>
                      <p className={`text-lg font-mono ${asset.requiredAmount > (asset.systemBalance ?? 0n) ? 'text-red-400' : 'text-white'}`}>
                        {formatBalance(asset.requiredAmount, asset.decimals)}
                        <span className="text-xs text-white/40 ml-1">{asset.symbol}</span>
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>

      <div className="p-6 border-t border-white/10">
        <LargeFullButton
          loading={loading}
          onClick={handleIssue}
          disabled={!amount || issueAmount === 0n || insufficientFunds}
        >
          <span className=""></span>Issue MULTI
        </LargeFullButton>
      </div>
    </div>
  );
}

function RedeemPage({
  onBack,
  assets,
  onRedeem,
  loading,
  multiBalance,
}: {
  loading: boolean;
  onBack: () => void;
  assets: Asset[];
  multiBalance: bigint;
  onRedeem: (amount: string) => Promise<void>;
}) {
  const [amount, setAmount] = useState("");

  // Clear amount when loading transitions from true to false (transaction complete)
  useEffect(() => {
    if (!loading) {
      setAmount("");
    }
  }, [loading]);

  const handleRedeem = async () => {
    if (!amount) return;
    await onRedeem(amount);
  };

  const { systemInfo } = useSystemInfo();
  const redeemAmount = formatStringToBigInt(amount, 8); // MULTI token has 8 decimals
  const multiRequired = redeemAmount ?? 0n;
  const multiAfterRedeem = multiBalance - multiRequired;

  const backingToReceive = assets.map(asset => {
    const backingToken = systemInfo?.backingTokens.find(token =>
      token.tokenInfo.canisterId.toString() === asset.canisterId
    );
    const amountPerMulti = backingToken && systemInfo
      ? Number(backingToken.backingUnit) / Number(systemInfo.supplyUnit)
      : 0;
    const receiveAmount = BigInt(Math.floor(Number(multiRequired) * amountPerMulti * (10 ** asset.decimals) / 100000000));
    return {
      ...asset,
      receiveAmount,
      balanceAfter: (asset.systemBalance ?? 0n) + receiveAmount
    };
  });

  const insufficientBalance = multiRequired > multiBalance;

  return (
    <div className="flex flex-col h-full">
      <Aurora className="w-full h-92">
        <div
          className="absolute h-92 inset-0 w-full h-full pointer-events-none z-0"
          style={{
            background:
              "linear-gradient(to bottom, rgba(4, 0, 20, 0.85) 0%, rgba(0, 18, 56, 0.6) 40%, rgba(75, 0, 59, 0.2) 80%, rgba(19, 0, 63, 0) 100%)",
          }}
        />
        <div className="p-6 pt-4 z-10 relative flex flex-col gap-4">
          <div className="flex justify-between w-full items-center">
            <button
              onClick={onBack}
              className="text-gray-400 hover:text-white transition-colors"
            >
              <FontAwesomeIcon icon={faChevronLeft} />
            </button>
            <h2 className="text-base text-white/60">Redeem MULTI</h2>
            <div className="w-6" />
          </div>

          <div className="mt-8 space-y-6">
            <div className="space-y-2">
              <label className="text-sm text-white/60">Amount to Redeem</label>
              <input
                type="number"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="Enter amount of MULTI to redeem"
                className="w-full bg-black/20 border border-white/20 text-white rounded-lg p-3 focus:outline-none focus:border-white/40"
              />
            </div>
          </div>
        </div>
      </Aurora>

      {/* Redeem Preview */}
      <div className="flex-1 p-6">
        <div className="bg-gray-800/50 backdrop-blur rounded-xl p-6 mb-4">
          <div className="flex flex-col gap-6">
            {/* Transaction Type Header */}
            <div className="flex items-center justify-between pb-4 border-b border-white/10">
              <div className="flex items-center gap-3">
                <div className="w-8 h-8 rounded-full bg-[#586CE1]/20 flex items-center justify-center">
                  <FontAwesomeIcon icon={faMinus} className="text-[#586CE1]" />
                </div>
                <div>
                  <h3 className="text-white font-medium">Redeem Preview</h3>
                  <p className="text-sm text-white/40">Transaction Details</p>
                </div>
              </div>
            </div>

            {/* MULTI Balance Changes */}
            <div className="py-4 border-b border-white/10">
              <div className="flex flex-col gap-2">
                <div className="flex justify-between items-center">
                  <p className="text-sm text-white/60">Available MULTI</p>
                  <p className="text-lg font-mono text-white">
                    {formatBalance(multiBalance, 8)}
                    <span className="text-xs text-white/40 ml-1">MULTI</span>
                  </p>
                </div>
                <div className="flex justify-between items-center">
                  <p className="text-sm text-white/60">Amount to Redeem</p>
                  <p className="text-lg font-mono text-white">
                    {redeemAmount ? formatBalance(redeemAmount, 8) : "-"}
                    <span className="text-xs text-white/40 ml-1">MULTI</span>
                  </p>
                </div>
                <div className="flex justify-between items-center">
                  <p className="text-sm text-white/60">MULTI After Redeem</p>
                  <p className={`text-lg font-mono ${insufficientBalance ? 'text-red-400' : 'text-white'}`}>
                    {formatBalance(multiAfterRedeem, 8)}
                    <span className="text-xs text-white/40 ml-1">MULTI</span>
                  </p>
                </div>
              </div>
            </div>

            {/* Assets to Receive */}
            <div>
              <p className="text-sm text-white/40 mb-3">Assets to Receive</p>
              <div className="space-y-4">
                {backingToReceive.map((asset) => (
                  <div key={asset.canisterId}>
                    <div className="flex items-center gap-2 mb-2">
                      <h4 className="font-semibold text-white">
                        {asset.name}
                        <span className="font-thin text-sm text-white/50 ml-1">
                          {asset.symbol}
                        </span>
                      </h4>
                    </div>
                    <div className="grid grid-cols-2 gap-4">
                      <div className="space-y-1">
                        <p className="text-xs text-white/60">Amount to Receive</p>
                        <p className="text-lg font-mono text-white">
                          {formatBalance(asset.receiveAmount, asset.decimals)}
                          <span className="text-xs text-white/40 ml-1">{asset.symbol}</span>
                        </p>
                      </div>
                      <div className="space-y-1">
                        <p className="text-xs text-white/60">Balance After Redeem</p>
                        <p className="text-lg font-mono text-white">
                          {formatBalance(asset.balanceAfter, asset.decimals)}
                          <span className="text-xs text-white/40 ml-1">{asset.symbol}</span>
                        </p>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>

      <div className="p-6 border-t border-white/10">
        <LargeFullButton
          loading={loading}
          onClick={handleRedeem}
          disabled={!amount || redeemAmount === 0n || insufficientBalance}
        >
          <span className=""></span>Redeem MULTI
        </LargeFullButton>
      </div>
    </div>
  );
}

function TransactionPreview({ selectedAsset, bigIntAmount }: { selectedAsset: Asset | null; bigIntAmount: bigint | null; }) {

  const walletBefore = selectedAsset?.walletBalance ?? 0n;
  const walletAfter = walletBefore - (bigIntAmount ?? 0n);


  return (
    <div className="flex-1 p-6">
      <div className="bg-gray-800/50 backdrop-blur rounded-xl p-6 mb-4">
        <div className="flex flex-col gap-6">
          {/* Transaction Type Header */}
          <div className="flex items-center justify-between pb-4 border-b border-white/10">
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-full bg-[#586CE1]/20 flex items-center justify-center">
                <FontAwesomeIcon icon={faArrowRightToBracket} className="text-[#586CE1]" />
              </div>
              <div>
                <h3 className="text-white font-medium">Deposit Preview</h3>
                <p className="text-sm text-white/40">Transaction Details</p>
              </div>
            </div>
          </div>

          {/* Before Transaction */}
          <div>
            <p className="text-sm text-white/40 mb-3">Current Balances</p>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-1">
                <p className="text-xs text-white/60">Wallet Balance</p>
                <p className="text-lg font-mono text-white">
                  {selectedAsset ? formatBalance(walletBefore, selectedAsset.decimals) : "-"}
                  <span className="text-xs text-white/40 ml-1">{selectedAsset?.symbol}</span>
                </p>
              </div>
              <div className="space-y-1">
                <p className="text-xs text-white/60">Deposited</p>
                <p className="text-lg font-mono text-white">
                  {selectedAsset ? formatBalance(selectedAsset.systemBalance ?? 0n, selectedAsset.decimals) : "-"}
                  <span className="text-xs text-white/40 ml-1">{selectedAsset?.symbol}</span>
                </p>
              </div>
            </div>
          </div>

          {/* Transaction Amount */}
          <div className="py-4 border-y border-white/10">
            <div className="flex justify-between items-center">
              <p className="text-sm text-white/60">Amount to Deposit</p>
              <p className="text-lg font-mono text-white">
                {bigIntAmount ? formatBalance(bigIntAmount, selectedAsset?.decimals ?? 0) : "-"}
                <span className="text-xs text-white/40 ml-1">{selectedAsset?.symbol}</span>
              </p>
            </div>
          </div>

          {/* After Transaction */}
          <div>
            <p className="text-sm text-white/40 mb-3">Expected Balance After</p>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-1">
                <p className="text-xs text-white/60">Wallet Balance</p>
                <p className="text-lg font-mono text-white">
                  {selectedAsset ? formatBalance(walletAfter, selectedAsset.decimals) : "-"}
                  <span className="text-xs text-white/40 ml-1">{selectedAsset?.symbol}</span>
                </p>
              </div>
              <div className="space-y-1">
                <p className="text-xs text-white/60">Deposited</p>
                <p className="text-lg font-mono text-white">
                  {selectedAsset ? formatBalance((selectedAsset.systemBalance ?? 0n) + (bigIntAmount ?? 0n), selectedAsset.decimals) : "-"}
                  <span className="text-xs text-white/40 ml-1">{selectedAsset?.symbol}</span>
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );

}

// Format balance for display
function formatBalance(balance: bigint, decimals: number): string {
  const divisor = BigInt(10 ** decimals);
  const whole = balance / divisor;
  const remainder = balance % divisor;

  if (remainder === 0n) {
    return whole.toString();
  }

  const decimalStr = remainder.toString().padStart(decimals, "0");
  // Remove trailing zeros
  const trimmedDecimal = decimalStr.replace(/0+$/, "");

  return trimmedDecimal.length > 0
    ? `${whole}.${trimmedDecimal}`
    : whole.toString();
};

function formatStringToBigInt(value: string | null, decimals: number | null): bigint {
  if (!value || !decimals) return BigInt(0);

  // Remove all non-numeric characters except decimal point
  const cleanValue = value.replace(/[^\d.]/g, '');

  // Split into whole and decimal parts
  let [whole = '0', decimal = ''] = cleanValue.split('.');

  // Remove leading zeros from whole part
  whole = whole.replace(/^0+/, '') || '0';

  // Pad or truncate decimal part to exact decimal places
  const paddedDecimal = decimal.padEnd(decimals, '0').slice(0, decimals);

  // Combine whole and decimal parts as pure integers
  const combinedValue = `${whole}${paddedDecimal}`;

  try {
    // Convert to BigInt, handling empty string case
    return BigInt(combinedValue);
  } catch {
    return BigInt(0);
  }
}