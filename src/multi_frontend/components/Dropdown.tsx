import { Menu, MenuItems, MenuItem, MenuButton } from '@headlessui/react';
import { Fragment, ReactNode, useState } from 'react';

type DropdownOption = {
    label: ReactNode;
    onClick: () => void;
    stayOpen?: boolean;
};

type DropdownMenuProps = {
    triggerLabel: ReactNode;
    options: DropdownOption[];
    className?: string;
};

export default function DropdownMenu({
    triggerLabel,
    options,
    className = '',
}: DropdownMenuProps) {
    const [open, setOpen] = useState(false);

    return (
        <Menu as="div" className={`relative inline-block text-left ${className}`} open={open} onClose={() => setOpen(false)}>
            <MenuButton as="button" onClick={() => setOpen((prev) => !prev)}>
                {triggerLabel}
            </MenuButton>
            <MenuItems modal={false} className="absolute p-2 z-50 right-0 mt-2 w-44 origin-top-right rounded-md bg-[#1D2432] shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none">
                {options.map((option, idx) =>
                    option.stayOpen ? (
                        <button
                            key={idx}
                            onClick={option.onClick}
                            className="hover:bg-[#586CE1] text-white group flex w-full rounded items-center px-4 py-2 text-sm font-medium"
                        >
                            {option.label}
                        </button>
                    ) : (
                        <MenuItem as={Fragment} key={idx}>
                            {({ focus }) => (
                                <button
                                    onClick={() => {
                                        option.onClick();
                                        setOpen(false);
                                    }}
                                    className={`${focus ? 'bg-[#586CE1] text-white' : 'text-white'
                                        } group flex w-full rounded items-center px-4 py-2 text-sm font-medium`}
                                >
                                    {option.label}
                                </button>
                            )}
                        </MenuItem>
                    )
                )}
            </MenuItems>
        </Menu>
    );
}
