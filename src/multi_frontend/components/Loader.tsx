import { twMerge } from 'tailwind-merge';

type LoaderSize = 'md' | 'sm' | 'lg' | 'xl';

export function Loader({ size = 'md' }: { size?: LoaderSize }) {
  return (
    <div
      className={twMerge(
        'w-8 h-8 border-4 border-white/20 border-t-white rounded-full animate-spin',
        getLoaderSizeStyle(size)
      )}
      role="status"
      aria-label="Loading"
    />
  );
}

function getLoaderSizeStyle(size: LoaderSize) {
  switch (size) {
    case 'md':
      return 'w-6 h-6 border-[3px]';

    case 'sm':
      return 'w-4 h-4 border-2';

    case 'lg':
      return 'w-8 h-8 border-4';

    case 'xl':
      return 'w-16 h-16 border-8';
  }
}
