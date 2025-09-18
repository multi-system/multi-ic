import { faChevronDown } from '@fortawesome/free-solid-svg-icons';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { Listbox, ListboxButton, ListboxOption, ListboxOptions } from '@headlessui/react';
import { ReactNode } from 'react';

interface SelectOption {
    value: string;
    label: string | ReactNode;
}

interface SelectProps {
    selectedValue: string;
    options: SelectOption[];
    placeholder: string;
    onChange: (value: string) => void;
}
interface SelectProps {
    selectedValue: string;
    options: SelectOption[];
    placeholder: string;
    onChange: (value: string) => void;
    label?: string;
}

function Select({ selectedValue, options, placeholder, onChange, label }: SelectProps) {
    const selectedOption = options.find(option => option.value === selectedValue);

    return (
        <div className="space-y-2">
            {label && <label className="text-sm text-white/60">{label}</label>}
            <Listbox value={selectedValue} onChange={onChange}>
                <div className="relative">
                    <ListboxButton className="w-full bg-black/20 border border-white/20 text-white rounded-lg p-3 focus:outline-none focus:border-white/40 text-left flex justify-between items-center">
                        <span className={selectedValue ? 'text-white' : 'text-white/60'}>
                            {selectedOption?.label || placeholder}
                        </span>
                        <FontAwesomeIcon icon={faChevronDown} className="h-3 w-3 text-white/60" />
                    </ListboxButton>
                    <ListboxOptions modal={false} className="absolute z-10 w-full mt-1 bg-gray-900 border border-white/20 rounded-lg p-2 max-h-60 overflow-auto">
                        {options.map((option) => (
                            <ListboxOption
                                key={option.value}
                                value={option.value}
                                className={({ active }) =>
                                    `cursor-pointer select-none p-3 ${active ? 'bg-white/5 rounded' : ''}`
                                }
                            >
                                {option.label}
                            </ListboxOption>
                        ))}
                    </ListboxOptions>
                </div>
            </Listbox>
        </div>
    );
}

export default Select;