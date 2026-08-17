import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Terms of Service",
  description: "The terms that govern using ProjectR.",
};

function LegalSection({ title, children }: { title: string; children: string }) {
  return (
    <section className="flex flex-col gap-2">
      <h2 className="text-lg font-semibold">{title}</h2>
      <p className="text-muted">{children}</p>
    </section>
  );
}

export default function TermsPage() {
  return (
    <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-8 px-6 py-16">
      <header className="flex flex-col gap-2">
        <p className="font-mono text-xs uppercase tracking-widest text-accent">
          Legal
        </p>
        <h1 className="font-display text-3xl font-semibold tracking-tight text-balance">
          Terms of Service
        </h1>
      </header>

      <div className="flex flex-col gap-6">
        <LegalSection title="What ProjectR is">
          ProjectR is a place to showcase and share what you&apos;re building. Every
          piece of content — updates, comments, media — belongs to a project.
          There&apos;s no general-purpose posting unrelated to something you&apos;re
          building. ProjectR is developed and operated by Kartik Sanil, an individual
          developer, referred to as &quot;we&quot; or &quot;us&quot; in these terms.
        </LegalSection>

        <LegalSection title="Acceptable use">
          Post your own work. Don&apos;t post content that infringes someone else&apos;s
          intellectual property, harasses or threatens others, is spam, or impersonates
          someone. We may remove content or suspend accounts that violate this, whether
          we find it ourselves or another user reports it to us.
        </LegalSection>

        <LegalSection title="Blocking and reporting">
          You can block another account at any time — once blocked, neither of you can
          follow or message the other, and you stop seeing each other&apos;s projects
          and updates. You can report a profile, project, comment, or update that
          violates these terms; we review reports and may remove content, warn, or
          suspend the account involved. Submitting a report you know to be false is
          itself a violation of these terms.
        </LegalSection>

        <LegalSection title="Your content">
          You own what you post. By posting it, you grant ProjectR a license to display
          it within the app and on the public project/profile pages you choose to
          share — nothing more.
        </LegalSection>

        <LegalSection title="Account termination">
          You can delete your account at any time from Settings. We may suspend or
          terminate accounts that violate these terms.
        </LegalSection>

        <LegalSection title="No warranty">
          ProjectR is provided as-is, without warranties of any kind. We don&apos;t
          guarantee the service will be uninterrupted or error-free.
        </LegalSection>

        <LegalSection title="Limitation of liability">
          To the extent permitted by law, ProjectR isn&apos;t liable for indirect or
          consequential damages arising from your use of the app.
        </LegalSection>

        <LegalSection title="Governing law">
          These terms are governed by the laws of India.
        </LegalSection>

        <LegalSection title="Changes">
          We may update these terms as the product evolves. Material changes will be
          reflected here.
        </LegalSection>

        <LegalSection title="Contact">
          Questions about these terms: 22kartiksanil@gmail.com.
        </LegalSection>

        <p className="font-mono text-xs text-muted">Last updated: August 2026</p>
      </div>
    </main>
  );
}
