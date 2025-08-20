import { twMerge } from 'tailwind-merge';
import { Loader } from './Loader';

type ButtonType = 'primary' | 'neutral' | 'destructive' | 'ghost';

export function Button({
  type = 'neutral',
  onClick,
  children,
  loading = false,
}: {
  type?: ButtonType;
  onClick: () => void;
  children: React.ReactNode;
  loading?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      className={twMerge(
        'px-4 py-2 py-2font-medium flex flex-row items-center justify-center gap-2 rounded-lg transition-colors',
        getButtonStyle(type)
      )}
    >
      <div className={loading ? 'invisible' : ''}>{children}</div>

      <div className={loading ? 'absolute' : 'invisible absolute'}>
        <Loader size="md" />
      </div>
    </button>
  );
}

function getButtonStyle(type: ButtonType) {
  switch (type) {
    case 'primary':
      return ' bg-[#586CE1] hover:bg-[#4056C7] text-white';

    case 'neutral':
      return 'bg-white/15 hover:bg-white/25 text-white';

    case 'destructive':
      return 'bg-rose-700 hover:bg-rose-600 text-white';

    case 'ghost':
      return 'bg-transperant hover:bg-white/5 text-white';
  }
}
