import Link from "next/link";

export function SiteHeader() {
  return (
    <header className="border-b border-border">
      <div className="mx-auto flex w-full max-w-4xl items-center justify-between px-6 py-4">
        <Link
          href="/"
          className="font-mono text-sm font-bold uppercase tracking-[0.2em] text-foreground"
        >
          ProjectR
        </Link>
        <Link
          href="/discover"
          className="font-mono text-xs uppercase tracking-widest text-muted transition-colors hover:text-accent"
        >
          Discover
        </Link>
      </div>
    </header>
  );
}
