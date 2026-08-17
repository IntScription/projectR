import Link from "next/link";
import { getTrendingProjects } from "@/lib/queries";

export default async function Home() {
  const projects = (await getTrendingProjects()).slice(0, 6);

  return (
    <main className="flex flex-1 flex-col">
      <section className="mx-auto flex w-full max-w-4xl flex-col items-center gap-6 px-6 py-24 text-center">
        <p className="font-mono text-xs font-bold uppercase tracking-[0.3em] text-accent">
          ProjectR
        </p>
        <h1 className="max-w-xl font-display text-5xl font-semibold tracking-tight text-balance">
          Project your work.
        </h1>
        <p className="max-w-md text-lg text-muted text-balance">
          A project-first social network for developers. No generic feed —
          every update belongs to something real being built.
        </p>
        <Link
          href="/discover"
          className="mt-2 rounded-full bg-accent px-6 py-3 font-medium text-background transition-opacity hover:opacity-90"
        >
          See what people are building
        </Link>
      </section>

      {projects.length > 0 && (
        <section className="border-t border-border bg-surface/40">
          <div className="mx-auto flex w-full max-w-4xl flex-col gap-6 px-6 py-16">
            <div className="flex items-baseline justify-between">
              <h2 className="font-mono text-xs uppercase tracking-widest text-muted">
                Trending now
              </h2>
              <Link
                href="/discover"
                className="font-mono text-xs uppercase tracking-widest text-accent transition-opacity hover:opacity-80"
              >
                View all →
              </Link>
            </div>
            <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {projects.map((project) => (
                <li key={project.id}>
                  <Link
                    href={`/p/${project.slug}`}
                    className="group flex h-full flex-col gap-3 rounded-lg border border-border bg-background p-4 transition-colors hover:border-accent"
                  >
                    <div className="aspect-video w-full overflow-hidden rounded bg-surface">
                      {project.cover_image_url && (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={project.cover_image_url}
                          alt=""
                          className="h-full w-full object-cover transition-transform duration-300 group-hover:scale-105"
                        />
                      )}
                    </div>
                    <div className="flex flex-col gap-1">
                      <span className="font-medium">{project.name}</span>
                      <span className="font-mono text-xs text-muted">
                        @{project.owner_username}
                      </span>
                    </div>
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        </section>
      )}
    </main>
  );
}
