import React, { ReactNode, useEffect, useRef } from "react";

interface AuroraContainerProps extends React.HTMLAttributes<HTMLDivElement> {
  children: ReactNode;
}

const Aurora: React.FC<AuroraContainerProps> = ({ children, className, ...props }) => {
  const layer1Ref = useRef<HTMLDivElement>(null);
  const layer2Ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let t = 0;
    let frameId: number;

    const animate = () => {
      t += 0.01;
      if (layer1Ref.current) {
        layer1Ref.current.style.transform = `translate(${Math.sin(t) * 30}px, ${Math.cos(t) * 30}px) scale(1.2)`;
      }
      if (layer2Ref.current) {
        layer2Ref.current.style.transform = `translate(${Math.cos(t) * 40}px, ${Math.sin(t) * 40}px) scale(1.1)`;
      }
      frameId = requestAnimationFrame(animate);
    };

    animate();
    return () => cancelAnimationFrame(frameId);
  }, []);

  return (
    <div
      className={`relative ${className || ""}`}
      style={{
        background: `radial-gradient(circle at 30% 30%, rgba(113, 88, 225, 0.6), transparent 70%), 
                     radial-gradient(circle at 70% 70%, #586ce1a1, transparent 70%), 
                     radial-gradient(circle at 50% 50%, rgba(88, 205, 241, 0.38), transparent 70%)`,
        backgroundBlendMode: "screen",
        color: "#fff",
      }}
      {...props}
    >
      <div
        ref={layer1Ref}
        className="absolute top-[-50%] left-[-50%] w-[200%] h-[200%] rounded-full pointer-events-none"
        style={{
          background: "radial-gradient(circle, rgba(88, 108, 225, 0.07) 0%, transparent 60%)",
          filter: "blur(80px)",
          mixBlendMode: "screen",
        }}
      />
      <div
        ref={layer2Ref}
        className="absolute top-[-50%] left-[-50%] w-[200%] h-[200%] rounded-full pointer-events-none"
        style={{
          background: "radial-gradient(circle, #589fe11c 0%, transparent 60%)",
          filter: "blur(80px)",
          mixBlendMode: "screen",
        }}
      />
      <div className="relative z-10">{children}</div>
    </div>
  );
};

export default Aurora;
