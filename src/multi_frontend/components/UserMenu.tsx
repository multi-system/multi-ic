import { Menu, MenuItems, MenuItem, MenuButton } from '@headlessui/react';
import { useState, useRef, Fragment } from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faChevronDown } from '@fortawesome/free-solid-svg-icons';
import Blockies from './Blockies';
import { useAuth } from '../contexts/AuthContext';
import { useSystemInfo } from '../contexts/SystemInfoContext';

export default function UserMenu() {
  const [copied, setCopied] = useState(false);

  const { principal, logout } = useAuth();

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(principal?.toText() ?? '');
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch (err) {
      console.error('Failed to copy:', err);
    }
  };

  return (
    <Menu as="div" className="relative inline-block text-left">
      <MenuButton className="inline-flex items-center h-10 duration-75 transition-colors rounded-full hover:bg-[#292F3C] bg-[#1D2432] pr-3 px-2 py-2 text-white select-none">
        <Blockies seed={principal?.toText() ?? ':('} />
        <span className="ml-3 mr-2 font-mono text-sm truncate max-w-[120px]">
          {principal?.toText().slice(0, 8)}...{principal?.toText().slice(-3)}
        </span>
        <FontAwesomeIcon className="h-3 opacity-50" icon={faChevronDown} />
      </MenuButton>

      <MenuItems className="absolute p-2 z-50 right-0 mt-2 w-44 origin-top-right rounded-md bg-[#1D2432] shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none">
        <div></div>
        <MenuItemWrapper
          stayOpen
          label={copied ? 'Copied!' : 'Copy Principal'}
          onClick={handleCopy}
        />
        <MenuItemWrapper label="Logout" onClick={logout} />
      </MenuItems>
    </Menu>
  );
}

function MenuItemWrapper({
  label,
  onClick,
  stayOpen = false,
}: {
  label: string;
  onClick: () => void;
  stayOpen?: boolean;
}) {
  if (stayOpen) {
    return (
      <button
        onClick={onClick}
        className={`${'hover:bg-[#586CE1] text-white'} group flex w-full rounded items-center px-4 py-2 text-sm font-medium`}
      >
        {label}
      </button>
    );
  }

  return (
    <MenuItem as={Fragment}>
      {({ focus }) => (
        <button
          onClick={onClick}
          className={`${
            focus ? 'bg-[#586CE1] text-white' : 'text-white'
          } group flex w-full rounded items-center px-4 py-2 text-sm font-medium`}
        >
          {label}
        </button>
      )}
    </MenuItem>
  );
}
