import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "How ProjectR collects, uses, and protects your data.",
};

function LegalSection({ title, children }: { title: string; children: string }) {
  return (
    <section className="flex flex-col gap-2">
      <h2 className="text-lg font-semibold">{title}</h2>
      <p className="text-muted">{children}</p>
    </section>
  );
}

export default function PrivacyPage() {
  return (
    <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-8 px-6 py-16">
      <header className="flex flex-col gap-2">
        <p className="font-mono text-xs uppercase tracking-widest text-accent">
          Legal
        </p>
        <h1 className="text-3xl font-semibold tracking-tight text-balance">
          Privacy Policy
        </h1>
      </header>

      <div className="flex flex-col gap-6">
        <LegalSection title="What we collect">
          When you create a ProjectR account, we receive your email address from Apple,
          Google, or directly from you, depending on how you sign in. Your ProjectR
          profile — display name, username, bio, avatar, banner, and links — is created
          separately from that sign-in identity; your skill levels are computed
          automatically from your own projects, never typed in separately. Projects,
          updates, comments, and any photos or clips you upload are stored to power the
          app. Direct messages you send to other users are stored so both participants
          can read the conversation. If you enable notifications, we store a device
          token with Apple to deliver them. If you connect a GitHub account, we store
          your GitHub access token encrypted in a secured vault — it&apos;s used only to
          read public repository metadata and to fork repositories on your behalf, and
          is never exposed to other users. If you block another user or report content,
          we store that action (who, what, and why) so it can be reviewed. If the app
          crashes or hits an unexpected error, technical details (device type, OS
          version, a stack trace) are sent to our crash-reporting provider so we can fix
          it. We also record which features you use — e.g. that a project was created
          or a portfolio PDF was generated — in our own database, never a third-party
          analytics network.
        </LegalSection>

        <LegalSection title="How we use it">
          Your account data and content are used to operate ProjectR: showing your
          profile and projects to other users (or the public, for shared links),
          powering search, discovery, and your auto-computed level, sending
          notifications about activity on your projects, delivering the messages you
          send, and reviewing reports of content or accounts that violate our terms.
          Crash reports are used only to find and fix bugs. Feature-usage records are
          used only to understand what&apos;s actually used and what isn&apos;t — never
          sold, never shared, and never used for advertising.
        </LegalSection>

        <LegalSection title="Third parties involved">
          ProjectR is built on Supabase (database, authentication, file storage,
          realtime messaging) and offers Sign in with Apple, Sign in with Google, and
          Sign in with GitHub as authentication options. Push notifications are
          delivered through Apple Push Notification service. Crash reports are sent to
          Sentry, a crash-reporting service — this is the only external
          analytics-adjacent service involved; the record of which features you use
          lives in our own database, not a third-party analytics network, and we
          don&apos;t integrate any advertising networks.
        </LegalSection>

        <LegalSection title="Your data, your control">
          You can change your username, profile photo, or banner at any time in
          Settings. You can block another user at any time from their profile, which
          also removes any follow relationship between you. You can permanently delete
          your account and everything attached to it — profile, projects, updates,
          comments, messages, likes, follows — from Settings → Delete Account. This is
          irreversible.
        </LegalSection>

        <LegalSection title="Retention">
          Your data is kept for as long as your account exists. Deleting your account
          removes it immediately, including uploaded photos, clips, and messages, and
          any reports you&apos;ve submitted. A report you filed about someone else&apos;s
          account or content is kept even if that account is later deleted, so patterns
          of abuse remain reviewable.
        </LegalSection>

        <LegalSection title="Children">
          ProjectR is not directed at children under 13, and we don&apos;t knowingly
          collect data from them.
        </LegalSection>

        <LegalSection title="Contact">
          ProjectR is developed and operated by Kartik Sanil, an individual developer.
          Questions about this policy: 22kartiksanil@gmail.com.
        </LegalSection>

        <p className="font-mono text-xs text-muted">Last updated: August 2026</p>
      </div>
    </main>
  );
}
