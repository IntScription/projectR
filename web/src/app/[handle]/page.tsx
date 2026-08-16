import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getProfileByUsername } from "@/lib/queries";

type Props = { params: Promise<{ handle: string }> };

function usernameFromHandle(handle: string) {
  return handle.startsWith("%40")
    ? decodeURIComponent(handle).slice(1)
    : handle.startsWith("@")
      ? handle.slice(1)
      : null;
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const username = usernameFromHandle((await params).handle);
  if (!username) return {};

  const result = await getProfileByUsername(username);
  if (!result) return {};

  const { profile } = result;
  const title = `${profile.display_name} (@${profile.username})`;
  const description = profile.bio ?? `${profile.display_name} on ProjectR.`;
  const images = profile.avatar_url ? [profile.avatar_url] : undefined;

  return {
    title,
    description,
    openGraph: {
      title,
      description,
      type: "profile",
      url: `/@${profile.username}`,
      images,
    },
    twitter: {
      card: "summary",
      title,
      description,
      images,
    },
  };
}

export default async function ProfilePage({ params }: Props) {
  const username = usernameFromHandle((await params).handle);
  if (!username) notFound();

  const result = await getProfileByUsername(username);
  if (!result) notFound();

  const { profile, projects } = result;

  return (
    <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-10 px-6 py-16">
      <header className="flex flex-col items-center gap-4 text-center">
        <div className="h-20 w-20 overflow-hidden rounded-full bg-surface ring-1 ring-border">
          {profile.avatar_url && (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={profile.avatar_url}
              alt={profile.display_name}
              className="h-full w-full object-cover"
            />
          )}
        </div>
        <div>
          <h1 className="text-2xl font-semibold">{profile.display_name}</h1>
          <p className="font-mono text-sm text-accent">@{profile.username}</p>
        </div>
        {profile.bio && <p className="max-w-md text-muted">{profile.bio}</p>}
        {profile.skills.length > 0 && (
          <ul className="flex flex-wrap justify-center gap-2">
            {profile.skills.map((skill) => (
              <li
                key={skill}
                className="rounded border border-border px-2.5 py-1 font-mono text-xs text-muted"
              >
                {skill}
              </li>
            ))}
          </ul>
        )}
        {profile.links.length > 0 && (
          <ul className="flex flex-wrap justify-center gap-4 text-sm">
            {profile.links.map((link) => (
              <li key={link.url}>
                <a
                  href={link.url}
                  className="text-accent underline underline-offset-4"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {link.label}
                </a>
              </li>
            ))}
          </ul>
        )}
      </header>

      <section className="flex flex-col gap-4">
        <h2 className="font-mono text-xs uppercase tracking-widest text-muted">
          Projects
        </h2>
        {projects.length === 0 ? (
          <p className="text-muted">No projects yet.</p>
        ) : (
          <ul className="grid gap-4 sm:grid-cols-2">
            {projects.map((project) => (
              <li key={project.id}>
                <Link
                  href={`/p/${project.slug}`}
                  className="flex flex-col gap-2 rounded border border-border bg-surface p-4 transition-colors hover:border-accent"
                >
                  <span className="font-medium">{project.name}</span>
                  {project.description && (
                    <span className="line-clamp-2 text-sm text-muted">
                      {project.description}
                    </span>
                  )}
                  <span className="font-mono text-xs uppercase tracking-wide text-accent">
                    {project.status}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
    </main>
  );
}
