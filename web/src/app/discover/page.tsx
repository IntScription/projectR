import type { Metadata } from "next";
import Link from "next/link";
import { CATEGORIES, getTrendingProjects, type Category } from "@/lib/queries";

export const metadata: Metadata = {
  title: "Discover",
  description: "See what people are building on ProjectR.",
};

type Props = { searchParams: Promise<{ category?: string }> };

function isCategory(value: string | undefined): value is Category {
  return !!value && (CATEGORIES as readonly string[]).includes(value);
}

export default async function DiscoverPage({ searchParams }: Props) {
  const requested = (await searchParams).category;
  const category = isCategory(requested) ? requested : undefined;
  const projects = await getTrendingProjects(category);

  return (
    <main className="mx-auto flex w-full max-w-4xl flex-1 flex-col gap-8 px-6 py-16">
      <header className="flex flex-col gap-2">
        <p className="font-mono text-xs uppercase tracking-widest text-accent">
          Discover
        </p>
        <h1 className="font-display text-3xl font-semibold tracking-tight text-balance">
          See what people are building.
        </h1>
      </header>

      <nav
        aria-label="Filter by category"
        className="flex flex-wrap gap-2"
      >
        <CategoryChip label="All" href="/discover" isActive={!category} />
        {CATEGORIES.map((value) => (
          <CategoryChip
            key={value}
            label={value}
            href={`/discover?category=${value}`}
            isActive={category === value}
          />
        ))}
      </nav>

      {projects.length === 0 ? (
        <p className="text-muted">Nothing here yet.</p>
      ) : (
        <ul className="grid gap-4 sm:grid-cols-2">
          {projects.map((project) => (
            <li key={project.id}>
              <Link
                href={`/p/${project.slug}`}
                className="flex flex-col gap-3 rounded border border-border bg-surface p-4 transition-colors hover:border-accent"
              >
                {project.cover_image_url && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={project.cover_image_url}
                    alt=""
                    className="h-36 w-full rounded object-cover"
                  />
                )}
                <div className="flex flex-col gap-1">
                  <span className="font-medium">{project.name}</span>
                  {project.description && (
                    <span className="line-clamp-2 text-sm text-muted">
                      {project.description}
                    </span>
                  )}
                </div>
                <div className="flex items-center justify-between text-xs">
                  <span className="font-mono text-muted">
                    @{project.owner_username}
                  </span>
                  <span className="font-mono uppercase tracking-wide text-accent">
                    {project.status}
                  </span>
                </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}

function CategoryChip({
  label,
  href,
  isActive,
}: {
  label: string;
  href: string;
  isActive: boolean;
}) {
  return (
    <Link
      href={href}
      className={`rounded-full border px-3 py-1.5 font-mono text-xs uppercase tracking-wide transition-colors ${
        isActive
          ? "border-accent bg-accent text-background"
          : "border-border text-muted hover:border-accent hover:text-accent"
      }`}
    >
      {label}
    </Link>
  );
}
