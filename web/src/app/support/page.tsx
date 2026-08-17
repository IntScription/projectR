import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Support",
  description: "Get help with ProjectR.",
};

export default function SupportPage() {
  return (
    <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-8 px-6 py-16">
      <header className="flex flex-col gap-2">
        <p className="font-mono text-xs uppercase tracking-widest text-accent">
          Support
        </p>
        <h1 className="text-3xl font-semibold tracking-tight text-balance">
          Need help with ProjectR?
        </h1>
      </header>

      <div className="flex flex-col gap-4">
        <p className="text-muted">
          ProjectR is developed and maintained by a single developer, Kartik Sanil.
          For bug reports, account issues, or general questions, email:
        </p>
        <a
          href="mailto:22kartiksanil@gmail.com"
          className="font-mono text-lg text-accent hover:underline"
        >
          22kartiksanil@gmail.com
        </a>
        <p className="text-muted">
          For questions about how your data is handled, see the{" "}
          <a href="/privacy" className="text-accent hover:underline">
            Privacy Policy
          </a>
          . For the rules of using ProjectR, see the{" "}
          <a href="/terms" className="text-accent hover:underline">
            Terms of Service
          </a>
          .
        </p>
      </div>
    </main>
  );
}
