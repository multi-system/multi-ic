export default function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="w-full flex flex-col gap-2">
      <h3 className="text-lg font-semibold text-white">{title}</h3>
      <div className="bg-white bg-opacity-5 w-full rounded-lg p-4">{children}</div>
    </div>
  );
}
