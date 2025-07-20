import MultiLogo from '../assets/multi_logo.svg';
import { useSystemInfo } from '../contexts/SystemInfoContext';
import SystemMetadata from './SystemMetadata';

export default function Footer() {
  const { systemInfo, lastRefresh, autoRefresh } = useSystemInfo();

  return (
    <footer className="mt-20 py-8 bg-black bg-opacity-30 backdrop-blur-md">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <SystemMetadata
          systemInfo={systemInfo}
          lastRefresh={lastRefresh}
          autoRefresh={autoRefresh}
        />
        <div className="flex items-center justify-center gap-2 text-gray-400 text-sm">
          <img src={MultiLogo} alt="Multi" className="h-5 w-5 opacity-60" />
          <p>Multi © 2025 - Built on the Internet Computer</p>
        </div>
      </div>
    </footer>
  );
}
