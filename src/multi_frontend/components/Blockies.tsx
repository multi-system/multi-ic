import { useEffect, useRef } from 'react';
import blockies from 'ethereum-blockies';

interface BlockiesProps {
  seed: string;
  size?: number; // Number of squares
  scale?: number; // Pixel size per square
  className?: string;
}

export default function Blockies({ seed, size = 6, scale = 4, className = '' }: BlockiesProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    if (canvasRef.current) {
      const icon = blockies.create({
        seed,
        size,
        scale,
      });
      const ctx = canvasRef.current.getContext('2d');
      if (ctx) {
        ctx.clearRect(0, 0, canvasRef.current.width, canvasRef.current.height);
        ctx.drawImage(icon, 0, 0);
      }
    }
  }, [seed, size, scale]);

  return (
    <canvas
      ref={canvasRef}
      width={size * scale}
      height={size * scale}
      className={`rounded-full ${className}`}
    />
  );
}
