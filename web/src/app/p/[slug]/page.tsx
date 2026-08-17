import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getProjectBySlug } from "@/lib/queries";

type Props = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const project = await getProjectBySlug((await params).slug);
  if (!project) return {};

  const description =
    project.description ?? `A project by ${project.owner.display_name} on ProjectR.`;

  return {
    title: project.name,
    description,
    openGraph: {
      title: project.name,
      description,
      type: "article",
      url: `/p/${project.slug}`,
      images: project.cover_image_url ? [project.cover_image_url] : undefined,
    },
    twitter: {
      card: project.cover_image_url ? "summary_large_image" : "summary",
      title: project.name,
      description,
      images: project.cover_image_url ? [project.cover_image_url] : undefined,
    },
  };
}

export default async function ProjectPage({ params }: Props) {
  const project = await getProjectBySlug((await params).slug);
  if (!project) notFound();

  return (
    <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-10 px-6 py-16">
      {project.cover_image_url && (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={project.cover_image_url}
          alt={project.name}
          className="aspect-video w-full rounded border border-border object-cover"
        />
      )}

      <header className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-3">
          <span className="rounded border border-border px-2.5 py-1 font-mono text-xs uppercase tracking-wide text-accent">
            {project.status}
          </span>
          <span className="font-mono text-xs uppercase tracking-wide text-muted">
            {project.category}
          </span>
        </div>
        <h1 className="font-display text-3xl font-semibold tracking-tight text-balance">
          {project.name}
        </h1>
        {project.description && (
          <p className="text-muted">{project.description}</p>
        )}
        <Link
          href={`/@${project.owner.username}`}
          className="flex items-center gap-2 text-sm"
        >
          <span className="h-6 w-6 overflow-hidden rounded-full bg-surface ring-1 ring-border">
            {project.owner.avatar_url && (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={project.owner.avatar_url}
                alt={project.owner.display_name}
                className="h-full w-full object-cover"
              />
            )}
          </span>
          <span className="text-muted">
            by <span className="text-foreground">{project.owner.display_name}</span>
          </span>
        </Link>
        <div className="flex flex-wrap gap-4 text-sm">
          {project.github_url && (
            <a
              href={project.github_url}
              className="text-accent underline underline-offset-4"
              target="_blank"
              rel="noopener noreferrer"
            >
              GitHub
            </a>
          )}
          {project.links.map((link) => (
            <a
              key={link.url}
              href={link.url}
              className="text-accent underline underline-offset-4"
              target="_blank"
              rel="noopener noreferrer"
            >
              {link.label}
            </a>
          ))}
        </div>
        {(project.tags.length > 0 || project.tech_stack.length > 0) && (
          <ul className="flex flex-wrap gap-2">
            {[...project.tech_stack, ...project.tags].map((tag) => (
              <li
                key={tag}
                className="rounded border border-border px-2.5 py-1 font-mono text-xs text-muted"
              >
                {tag}
              </li>
            ))}
          </ul>
        )}
      </header>

      {project.project_media.length > 0 && (
        <section className="grid gap-3 sm:grid-cols-2">
          {project.project_media.map((media) => (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              key={media.id}
              src={media.url}
              alt=""
              className="aspect-video w-full rounded border border-border object-cover"
            />
          ))}
        </section>
      )}

      <section className="flex flex-col gap-4">
        <h2 className="font-mono text-xs uppercase tracking-widest text-muted">
          Updates
        </h2>
        {project.project_updates.length === 0 ? (
          <p className="text-muted">No updates yet.</p>
        ) : (
          <ol className="flex flex-col gap-4 border-l border-border pl-4">
            {project.project_updates.map((update) => (
              <li key={update.id} className="flex flex-col gap-1">
                <time className="font-mono text-xs text-muted">
                  {new Date(update.created_at).toLocaleDateString(undefined, {
                    month: "short",
                    day: "numeric",
                  })}
                </time>
                <p>{update.body}</p>
              </li>
            ))}
          </ol>
        )}
      </section>
    </main>
  );
}
