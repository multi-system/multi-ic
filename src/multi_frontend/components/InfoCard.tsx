export default function InfoCard({
  label,
  value,
  unitName,
}: {
  label: string;
  value: string;
  unitName: string;
}) {
  return (
    <div className="bg-white bg-opacity-5 w-full rounded-lg p-4">
      <p className="text-sm text-gray-400">{label}</p>
      <p className="text-2xl font-bold text-white">{value}</p>
      <p className="text-xs text-gray-500 mt-1">{unitName}</p>
    </div>
  );
}
