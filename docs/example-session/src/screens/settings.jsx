export default function settings() {
  const { data, error } = useQuery();
  if (error) return <div>{error.status}</div>;
  if (!data) return <Spinner />;
  return <List items={data} />;
}
