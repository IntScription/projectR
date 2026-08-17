import Link from "next/link";

export function SiteFooter() {
  return (
    <footer className="border-t border-border">
      <div className="mx-auto flex w-full max-w-4xl flex-col gap-4 px-6 py-8 text-sm sm:flex-row sm:items-center sm:justify-between">
        <p className="font-mono text-xs uppercase tracking-widest text-muted">
          © {new Date().getFullYear()} ProjectR
        </p>
        <nav className="flex flex-wrap gap-x-6 gap-y-2 text-muted">
          <Link href="/discover" className="transition-colors hover:text-accent">
            Discover
          </Link>
          <Link href="/support" className="transition-colors hover:text-accent">
            Support
          </Link>
          <Link href="/privacy" className="transition-colors hover:text-accent">
            Privacy
          </Link>
          <Link href="/terms" className="transition-colors hover:text-accent">
            Terms
          </Link>
        </nav>
      </div>
    </footer>
  );
}
