import { Fragment, ReactNode, useState, useRef } from "react";
import { Transition } from "@headlessui/react";
import { createPortal } from "react-dom";

interface TooltipProps {
    tip: string;
    children: ReactNode;
}

const Tooltip: React.FC<TooltipProps> = ({ tip, children }) => {
    const [isHovered, setIsHovered] = useState(false);
    const [tooltipPos, setTooltipPos] = useState({ top: 0, left: 0 });
    const childRef = useRef<HTMLDivElement>(null);
    const tooltipRef = useRef<HTMLDivElement>(null);

    // Function to calculate tooltip position
    const updatePosition = () => {
        if (!childRef.current || !tooltipRef.current) return;

        const childRect = childRef.current.getBoundingClientRect();
        const tooltipRect = tooltipRef.current.getBoundingClientRect();
        const padding = 8;

        let top = window.scrollY + childRect.top - tooltipRect.height - padding;
        let left = window.scrollX + childRect.left + childRect.width / 2 - tooltipRect.width / 2;

        // Clamp horizontally
        left = Math.max(padding + window.scrollX, Math.min(left, window.scrollX + window.innerWidth - tooltipRect.width - padding));

        // Flip vertically if it would go off top
        if (top < window.scrollY + padding) {
            top = window.scrollY + childRect.bottom + padding;
        }

        setTooltipPos({ top, left });
    };

    return (
        <>
            <div
                ref={childRef}
                className="inline-flex"
                onMouseEnter={() => setIsHovered(true)}
                onMouseLeave={() => setIsHovered(false)}
            >
                {children}
            </div>

            {createPortal(
                <Transition
                    as={Fragment}
                    show={isHovered}
                    enter="transition ease-out duration-200"
                    enterFrom="opacity-0 translate-y-1"
                    enterTo="opacity-100 translate-y-0"
                    leave="transition ease-in duration-150"
                    leaveFrom="opacity-100 translate-y-0"
                    leaveTo="opacity-0 translate-y-1"
                    beforeEnter={updatePosition} // <-- measure after tooltip mounts
                >
                    <div
                        ref={tooltipRef}
                        style={{
                            position: "absolute",
                            top: tooltipPos.top,
                            left: tooltipPos.left,
                            maxWidth: "90vw",
                            zIndex: 9999,
                        }}
                        className="px-3 py-1 rounded-md bg-gray-800 text-white text-sm whitespace-nowrap pointer-events-none shadow-lg"
                    >
                        {tip}
                    </div>
                </Transition>,
                document.body
            )}
        </>
    );
};

export default Tooltip;
