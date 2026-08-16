//! Real local git operations — Forge Phase 2. Clone (shallow, HTTPS,
//! token-authenticated), working-tree status, diffs, and local
//! staging/commit, all via `gix` (gitoxide). Deliberately does **not**
//! implement push: `gix`'s write-side wire protocol isn't reliable yet
//! (confirmed during planning), so syncing a local commit to GitHub is
//! done from the Swift side via the existing, already-proven GitHub REST
//! Git Data API instead — this crate only ever needs to hand back the
//! diff content for the files a commit touched, not speak git's smart
//! HTTP protocol itself.

use std::fs;
use std::num::NonZeroU32;
use std::path::Path;

use gix::bstr::ByteSlice;
use gix::objs::tree::EntryKind;

/// Every function here fails through this one error type — the bridge's
/// first real error handling (`engine_status` had no failure mode at
/// all). Each case is broad on purpose: Swift only ever needs enough to
/// show a real message, not to pattern-match on git internals.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum ForgeError {
    #[error("Couldn't reach the repository: {0}")]
    Network(String),
    #[error("Couldn't open the local repository: {0}")]
    Repository(String),
    #[error("Couldn't read or write a local file: {0}")]
    Io(String),
    #[error("Git operation failed: {0}")]
    Git(String),
}

/// One changed path in the working tree, relative to the repo root.
#[derive(uniffi::Record)]
pub struct FileStatus {
    pub path: String,
    pub change: ChangeKind,
}

#[derive(uniffi::Enum)]
pub enum ChangeKind {
    Added,
    Modified,
    Deleted,
}

/// Shallow clone over HTTPS. `token` is embedded directly in the clone
/// URL as the basic-auth username (GitHub's own documented pattern for
/// token auth over HTTPS) rather than wired through `gix`'s credential-
/// callback machinery — simpler, and this crate never stores the token
/// anywhere, it only ever sees it for the duration of this one call.
#[uniffi::export]
pub fn clone_repository(url: String, token: String, local_path: String, depth: u32) -> Result<(), ForgeError> {
    let authed_url = embed_token(&url, &token)?;
    let depth = NonZeroU32::new(depth).unwrap_or_else(|| NonZeroU32::new(1).expect("1 is non-zero"));

    let mut checkout = gix::prepare_clone(authed_url.as_str(), local_path)
        .map_err(|e| ForgeError::Network(e.to_string()))?
        .with_shallow(gix::remote::fetch::Shallow::DepthAtRemote(depth))
        .fetch_then_checkout(gix::progress::Discard, &gix::interrupt::IS_INTERRUPTED)
        .map_err(|e| ForgeError::Network(e.to_string()))?
        .0;

    checkout
        .main_worktree(gix::progress::Discard, &gix::interrupt::IS_INTERRUPTED)
        .map_err(|e| ForgeError::Git(e.to_string()))?;
    Ok(())
}

fn embed_token(url: &str, token: &str) -> Result<String, ForgeError> {
    let rest = url
        .strip_prefix("https://")
        .ok_or_else(|| ForgeError::Git("Only https:// repository URLs are supported.".into()))?;
    Ok(format!("https://{token}@{rest}"))
}

/// Real `git status` — added/modified/deleted paths in the working tree.
/// This is the exact gap `ForgeDashboardView` previously called out as
/// having "no meaning" without a local clone.
///
/// Deliberately compares the working tree directly against `HEAD`'s tree
/// (a manual recursive walk, below) rather than using `gix`'s index-based
/// `Repository::status()` — this app never maintains a separate staging
/// area distinct from "the files a commit touches" (`stage_and_commit`
/// writes straight to a new tree/commit, it doesn't update the on-disk
/// index), so an index-vs-worktree comparison would report stale results
/// the moment something's been committed. Comparing against HEAD directly
/// has no such staleness to manage.
#[uniffi::export]
pub fn working_tree_status(local_path: String) -> Result<Vec<FileStatus>, ForgeError> {
    let repo = open(&local_path)?;
    let head_tree_id = repo.head_tree_id().map_err(|e| ForgeError::Git(e.to_string()))?;
    let tree = repo
        .find_object(head_tree_id)
        .map_err(|e| ForgeError::Git(e.to_string()))?
        .into_tree();

    let mut head_files = std::collections::BTreeMap::new();
    collect_tree_files(&repo, &tree, String::new(), &mut head_files)?;

    let mut worktree_files = std::collections::BTreeMap::new();
    collect_worktree_files(Path::new(&local_path), Path::new(&local_path), &mut worktree_files)?;

    let mut out = Vec::new();
    for (path, head_content) in &head_files {
        match worktree_files.get(path) {
            None => out.push(FileStatus { path: path.clone(), change: ChangeKind::Deleted }),
            Some(current) if current != head_content => {
                out.push(FileStatus { path: path.clone(), change: ChangeKind::Modified })
            }
            _ => {}
        }
    }
    for path in worktree_files.keys() {
        if !head_files.contains_key(path) {
            out.push(FileStatus { path: path.clone(), change: ChangeKind::Added });
        }
    }
    Ok(out)
}

/// Recursively collects `(relative path -> blob content)` for every blob
/// reachable from `tree` — content, not just the blob id, since the
/// simplest correct way to detect a "modified" file here is comparing
/// bytes directly rather than re-deriving a hash by hand.
fn collect_tree_files(
    repo: &gix::Repository,
    tree: &gix::Tree<'_>,
    prefix: String,
    out: &mut std::collections::BTreeMap<String, Vec<u8>>,
) -> Result<(), ForgeError> {
    let decoded = tree.decode().map_err(|e| ForgeError::Git(e.to_string()))?;
    for entry in decoded.entries {
        let name = entry.filename.to_str_lossy();
        let path = if prefix.is_empty() { name.into_owned() } else { format!("{prefix}/{name}") };
        match entry.mode.kind() {
            gix::objs::tree::EntryKind::Tree => {
                let subtree = repo
                    .find_object(entry.oid)
                    .map_err(|e| ForgeError::Git(e.to_string()))?
                    .into_tree();
                collect_tree_files(repo, &subtree, path, out)?;
            }
            gix::objs::tree::EntryKind::Blob | gix::objs::tree::EntryKind::BlobExecutable => {
                let blob = repo.find_object(entry.oid).map_err(|e| ForgeError::Git(e.to_string()))?;
                out.insert(path, blob.data.clone());
            }
            _ => {}
        }
    }
    Ok(())
}

/// Recursively collects `(relative path -> file content)` for every real
/// file under `dir`, skipping `.git` — the working tree's side of the
/// comparison above.
fn collect_worktree_files(
    root: &Path,
    dir: &Path,
    out: &mut std::collections::BTreeMap<String, Vec<u8>>,
) -> Result<(), ForgeError> {
    let entries = fs::read_dir(dir).map_err(|e| ForgeError::Io(e.to_string()))?;
    for entry in entries {
        let entry = entry.map_err(|e| ForgeError::Io(e.to_string()))?;
        let path = entry.path();
        let file_type = entry.file_type().map_err(|e| ForgeError::Io(e.to_string()))?;
        if file_type.is_dir() {
            if path.file_name().and_then(|n| n.to_str()) == Some(".git") {
                continue;
            }
            collect_worktree_files(root, &path, out)?;
        } else if file_type.is_file() {
            let rela = path
                .strip_prefix(root)
                .map_err(|e| ForgeError::Io(e.to_string()))?
                .to_string_lossy()
                .replace('\\', "/");
            let content = fs::read(&path).map_err(|e| ForgeError::Io(e.to_string()))?;
            out.insert(rela, content);
        }
    }
    Ok(())
}

/// Unified-style diff text for one file's working-tree change against
/// `HEAD` — plain +/- line rendering (matches the existing REST-backed
/// commit-diff viewer's own "no syntax highlighting yet" scope), not a
/// full patch format.
#[uniffi::export]
pub fn file_diff(local_path: String, path: String) -> Result<String, ForgeError> {
    let repo = open(&local_path)?;
    let old_text = read_head_blob(&repo, &path).unwrap_or_default();
    let new_text = fs::read_to_string(Path::new(&local_path).join(&path)).unwrap_or_default();

    let old_lines: Vec<&str> = old_text.lines().collect();
    let new_lines: Vec<&str> = new_text.lines().collect();
    let diff = similar::TextDiff::from_slices(&old_lines, &new_lines);

    let mut out = String::new();
    for change in diff.iter_all_changes() {
        let sign = match change.tag() {
            similar::ChangeTag::Delete => "-",
            similar::ChangeTag::Insert => "+",
            similar::ChangeTag::Equal => " ",
        };
        out.push_str(sign);
        out.push_str(change.value());
        out.push('\n');
    }
    Ok(out)
}

fn read_head_blob(repo: &gix::Repository, path: &str) -> Option<String> {
    let head_tree = repo.head_tree_id().ok()?;
    let tree = repo.find_object(head_tree).ok()?.into_tree();
    let entry = tree.lookup_entry_by_path(path).ok()??;
    let blob = repo.find_object(entry.object_id()).ok()?;
    String::from_utf8(blob.data.clone()).ok()
}

#[uniffi::export]
pub fn read_working_file(local_path: String, path: String) -> Result<String, ForgeError> {
    fs::read_to_string(Path::new(&local_path).join(&path)).map_err(|e| ForgeError::Io(e.to_string()))
}

#[uniffi::export]
pub fn write_working_file(local_path: String, path: String, content: String) -> Result<(), ForgeError> {
    let full_path = Path::new(&local_path).join(&path);
    if let Some(parent) = full_path.parent() {
        fs::create_dir_all(parent).map_err(|e| ForgeError::Io(e.to_string()))?;
    }
    fs::write(full_path, content).map_err(|e| ForgeError::Io(e.to_string()))
}

/// Stages the given paths (reading their current on-disk content) and
/// writes a real local commit object on top of `HEAD`, moving `HEAD` to
/// point at it. Returns the new commit's sha. Uses the tree editor
/// (`Repository::edit_tree`, explicitly aliased to `git2`'s treebuilder
/// in gix's own docs) rather than the full index-staging machinery —
/// simpler for "commit these specific files," which is all this app's
/// editor ever needs.
#[uniffi::export]
pub fn stage_and_commit(
    local_path: String,
    paths: Vec<String>,
    message: String,
    author_name: String,
    author_email: String,
) -> Result<String, ForgeError> {
    let repo = open(&local_path)?;
    let head_tree_id = repo.head_tree_id().map_err(|e| ForgeError::Git(e.to_string()))?;
    let mut editor = repo
        .edit_tree(head_tree_id)
        .map_err(|e| ForgeError::Git(e.to_string()))?;

    for path in &paths {
        let content = fs::read(Path::new(&local_path).join(path)).map_err(|e| ForgeError::Io(e.to_string()))?;
        let blob_id = repo
            .write_blob(&content)
            .map_err(|e| ForgeError::Git(e.to_string()))?;
        editor
            .upsert(path.as_str(), EntryKind::Blob, blob_id)
            .map_err(|e| ForgeError::Git(e.to_string()))?;
    }

    let new_tree_id = editor.write().map_err(|e| ForgeError::Git(e.to_string()))?;

    let signature = gix::actor::Signature {
        name: author_name.as_str().into(),
        email: author_email.as_str().into(),
        time: gix::date::Time::now_local_or_utc(),
    };
    let mut committer_buf = gix::date::parse::TimeBuf::default();
    let mut author_buf = gix::date::parse::TimeBuf::default();

    let head_commit_id = repo
        .head_id()
        .map_err(|e| ForgeError::Git(e.to_string()))?
        .detach();

    let commit_id = repo
        .commit_as(
            signature.to_ref(&mut committer_buf),
            signature.to_ref(&mut author_buf),
            "HEAD",
            message,
            new_tree_id.detach(),
            [head_commit_id],
        )
        .map_err(|e| ForgeError::Git(e.to_string()))?;

    Ok(commit_id.to_string())
}

fn open(local_path: &str) -> Result<gix::Repository, ForgeError> {
    gix::open(local_path).map_err(|e| ForgeError::Repository(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Bootstraps a real, on-disk repo with one initial commit — entirely
    /// offline (no network), since `clone_repository` is the only
    /// function here that actually needs one, and it's the least novel
    /// part of this crate (gitoxide's fetch/clone path is already the
    /// mature half — the local plumbing exercised here is the genuinely
    /// new code this test is actually meant to catch regressions in).
    fn init_repo_with_first_commit(dir: &std::path::Path) -> String {
        std::fs::write(dir.join("README.md"), "hello\n").unwrap();
        let repo = gix::init(dir).unwrap();
        let blob_id = repo.write_blob(b"hello\n").unwrap();
        let mut editor = repo.edit_tree(gix::ObjectId::empty_tree(repo.object_hash())).unwrap();
        editor.upsert("README.md", EntryKind::Blob, blob_id).unwrap();
        let tree_id = editor.write().unwrap();

        let signature = gix::actor::Signature {
            name: "Test".into(),
            email: "test@example.com".into(),
            time: gix::date::Time::now_local_or_utc(),
        };
        let mut committer_buf = gix::date::parse::TimeBuf::default();
        let mut author_buf = gix::date::parse::TimeBuf::default();
        let commit_id = repo
            .commit_as(
                signature.to_ref(&mut committer_buf),
                signature.to_ref(&mut author_buf),
                "HEAD",
                "Initial commit",
                tree_id.detach(),
                gix::commit::NO_PARENT_IDS,
            )
            .unwrap();
        commit_id.to_string()
    }

    #[test]
    fn status_is_clean_right_after_init() {
        let dir = tempfile::tempdir().unwrap();
        init_repo_with_first_commit(dir.path());

        let status = working_tree_status(dir.path().to_string_lossy().into_owned()).unwrap();
        assert!(status.is_empty(), "expected no changes right after the first commit");
    }

    #[test]
    fn status_detects_a_real_edit() {
        let dir = tempfile::tempdir().unwrap();
        let local_path = dir.path().to_string_lossy().into_owned();
        init_repo_with_first_commit(dir.path());

        write_working_file(local_path.clone(), "README.md".into(), "hello\nworld\n".into()).unwrap();

        let status = working_tree_status(local_path.clone()).unwrap();
        assert_eq!(status.len(), 1);
        assert_eq!(status[0].path, "README.md");
        assert!(matches!(status[0].change, ChangeKind::Modified));

        let diff = file_diff(local_path, "README.md".into()).unwrap();
        assert!(diff.contains("+world"), "diff was: {diff}");
    }

    #[test]
    fn stage_and_commit_writes_a_real_commit_and_clears_status() {
        let dir = tempfile::tempdir().unwrap();
        let local_path = dir.path().to_string_lossy().into_owned();
        let first_commit = init_repo_with_first_commit(dir.path());

        write_working_file(local_path.clone(), "README.md".into(), "hello\nworld\n".into()).unwrap();
        let second_commit = stage_and_commit(
            local_path.clone(),
            vec!["README.md".into()],
            "Update README".into(),
            "Test".into(),
            "test@example.com".into(),
        )
        .unwrap();

        assert_ne!(first_commit, second_commit, "commit should have moved HEAD forward");

        // The real regression this guards against: after committing,
        // status must go back to clean — it would stay stuck showing
        // "Modified" if `stage_and_commit` compared against a stale
        // index instead of the tree it just wrote.
        let status = working_tree_status(local_path.clone()).unwrap();
        assert!(status.is_empty(), "expected clean status after committing");

        let read_back = read_working_file(local_path, "README.md".into()).unwrap();
        assert_eq!(read_back, "hello\nworld\n");
    }

    #[test]
    fn detects_added_and_deleted_files() {
        let dir = tempfile::tempdir().unwrap();
        let local_path = dir.path().to_string_lossy().into_owned();
        init_repo_with_first_commit(dir.path());

        write_working_file(local_path.clone(), "NEW.md".into(), "new file\n".into()).unwrap();
        std::fs::remove_file(dir.path().join("README.md")).unwrap();

        let mut status = working_tree_status(local_path).unwrap();
        status.sort_by(|a, b| a.path.cmp(&b.path));
        assert_eq!(status.len(), 2);
        assert_eq!(status[0].path, "NEW.md");
        assert!(matches!(status[0].change, ChangeKind::Added));
        assert_eq!(status[1].path, "README.md");
        assert!(matches!(status[1].change, ChangeKind::Deleted));
    }
}
