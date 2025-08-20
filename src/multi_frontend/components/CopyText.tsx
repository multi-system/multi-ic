import { useState } from 'react';
import { Transition } from '@headlessui/react';

interface CopyTextProps {
  copyText: string;
  children: React.ReactNode; // what’s displayed
}

export default function CopyText({ copyText, children }: CopyTextProps) {
  const [showTooltip, setShowTooltip] = useState(false);
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(copyText);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch (err) {
      console.error('Failed to copy: ', err);
    }
  };

  return (
    <div
      className="relative inline-block"
      onMouseEnter={() => setShowTooltip(true)}
      onMouseLeave={() => setShowTooltip(false)}
    >
      <button onClick={handleCopy} className="text-gray-800 hover:text-blue-600 transition-colors">
        {children}
      </button>

      {/* Tooltip */}
      <Transition
        show={showTooltip}
        enter="transition-opacity duration-150"
        enterFrom="opacity-0"
        enterTo="opacity-100"
        leave="transition-opacity duration-150"
        leaveFrom="opacity-100"
        leaveTo="opacity-0"
      >
        <div className="absolute -top-8 left-1/2 -translate-x-1/2 rounded bg-gray-900 text-white text-xs px-2 py-1 whitespace-nowrap shadow-lg">
          {copied ? 'Copied!' : 'Copy'}
        </div>
      </Transition>
    </div>
  );
}
