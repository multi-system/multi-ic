import { faChevronDown, faChevronUp } from '@fortawesome/free-solid-svg-icons';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import React from 'react';

interface IncrementalInputProps {
  value: number | string;
  onChange: (e: React.ChangeEvent<HTMLInputElement>) => void;
  step?: number;
  placeholder?: string;
  min?: number;
  max?: number;
}

export const IncrementalInput: React.FC<IncrementalInputProps> = ({
  value,
  onChange,
  step = 1,
  min,
  max,
  placeholder,
}) => {
  const decimals = (n: number) => {
    if (!isFinite(n)) return 0;
    const s = String(n);
    return s.includes('.') ? s.split('.')[1].length : 0;
  };

  const adjustValue = (dir: 'up' | 'down') => {
    const cur = parseFloat(String(value));
    const currentValue = Number.isNaN(cur) ? 0 : cur;

    const places = Math.max(decimals(step), decimals(currentValue), 0);
    const factor = Math.pow(10, places);

    const intCur = Math.round(currentValue * factor);
    const intStep = Math.round(step * factor);
    const intNew = dir === 'up' ? intCur + intStep : intCur - intStep;
    const newVal = intNew / factor;

    if (min !== undefined && newVal < min) return;
    if (max !== undefined && newVal > max) return;

    const synthetic = {
      target: { value: String(Number(newVal.toFixed(places))) },
    } as React.ChangeEvent<HTMLInputElement>;

    onChange(synthetic);
  };

  return (
    <div className="relative group">
      <input
        placeholder={placeholder}
        type="text"
        value={value}
        onChange={onChange}
        className="w-32 px-3 py-2 rounded-md bg-white bg-opacity-10 text-white border border-white border-opacity-20 focus:outline-none focus:ring-2 focus:ring-[#586CE1]"
      />

      {/* custom buttons */}
      <div className="absolute  border-l border-white border-opacity-10 right-0 top-1/2 -translate-y-1/2 flex flex-col opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 transition-opacity duration-150">
        <button
          type="button"
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => adjustValue('up')}
          className="w-8 h-5  flex items-center justify-center text-gray-300 hover:text-white hover:bg-white/10 rounded-tr"
        >
          <FontAwesomeIcon icon={faChevronUp} size="2xs" />
        </button>
        <button
          type="button"
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => adjustValue('down')}
          className="w-8 h-5  flex items-center justify-center text-gray-300 hover:text-white hover:bg-white/10 rounded-br"
        >
          <FontAwesomeIcon icon={faChevronDown} size="2xs" />
        </button>
      </div>
    </div>
  );
};
