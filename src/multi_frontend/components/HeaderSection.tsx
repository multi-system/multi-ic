export default function HeaderSection({
  header,
  children,
}: {
  header: string;
  children: React.ReactNode;
}) {
  return (
    <div className="w-full flex flex-col gap-2">
      <h3 className="text-lg font-semibold text-white">{header}</h3>
      <div className="bg-white bg-opacity-5 w-full rounded-lg p-4">{children}</div>
    </div>
  );
}
