import { REFRESH_INTERVAL } from '../utils/constants';
import { SystemInfo } from '../utils/types';

export default function SystemMetadata({
  systemInfo,
  lastRefresh,
  autoRefresh,
}: {
  systemInfo: SystemInfo | null | undefined;
  lastRefresh: Date;
  autoRefresh: boolean;
}) {
  if (!systemInfo) {
    return null;
  }
  return (
    <div className="space-y-2 text-sm">
      <div className="flex justify-between">
        <span className="text-gray-500">Supply Unit</span>
        <span className="text-gray-500 font-mono">{systemInfo.supplyUnit.toString()}</span>
      </div>
      <div className="flex justify-between">
        <span className="text-gray-500">Multi Token</span>
        <span className="text-gray-500 font-mono text-xs">
          {systemInfo.multiToken.canisterId.toString()}
        </span>
      </div>
      <div className="flex justify-between">
        <span className="text-gray-500">Governance Token</span>
        <span className="text-gray-500 font-mono text-xs">
          {systemInfo.governanceToken.canisterId.toString()}
        </span>
      </div>
      <div className="flex justify-between items-center pt-2 border-t border-white border-opacity-10">
        <span className="text-xs text-gray-500">
          Last updated: {lastRefresh.toLocaleTimeString()}
        </span>
        {autoRefresh && (
          <span className="text-xs text-gray-500">Auto-refresh: {REFRESH_INTERVAL / 1000}s</span>
        )}
      </div>
    </div>
  );
}
