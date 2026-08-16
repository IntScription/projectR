export default function Home() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-4 px-6 text-center">
      <p className="font-mono text-xs uppercase tracking-widest text-accent">
        ProjectR
      </p>
      <h1 className="max-w-xl text-4xl font-semibold tracking-tight text-balance">
        Project your work.
      </h1>
      <p className="max-w-md text-muted">
        A social network for people who build things. The iOS app is where
        projects get created — this site is where they get shared.
      </p>
    </main>
  );
}
