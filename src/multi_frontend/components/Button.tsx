import { twMerge } from 'tailwind-merge';

type ButtonType = 'primary' | 'neutral' | 'destructive' | 'ghost';

export function Button({
  type = 'neutral',
  onClick,
  children,
}: {
  type?: ButtonType;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className={twMerge(
        'px-4 py-2 py-2font-medium flex flex-row items-center justify-center gap-2 rounded-lg transition-colors',
        getButtonStyle(type)
      )}
    >
      {children}
    </button>
  );
}

function getButtonStyle(type: ButtonType) {
  switch (type) {
    case 'primary':
      return ' bg-[#586CE1] hover:bg-[#4056C7] text-white';

    case 'neutral':
      return 'bg-gray-800 hover:bg-gray-700 text-white';

    case 'destructive':
      return 'bg-rose-700 hover:bg-rose-600 text-white';

    case 'ghost':
      return 'bg-transperant hover:bg-white/5 text-white';
  }
}
