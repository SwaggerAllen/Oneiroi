import { useState } from 'react';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';

export interface GithubTokenProps {
  residentName: string;
  status: { present: boolean; stored_at: string | null };
  onStore: (token: string) => void;
  onRevoke: () => void;
}

// The witness's GitHub read token (gaia#24, the witness, 2026-11-08):
// what the resident's pull request reads (pr_meta, pr_diffs) send, set,
// rotated and revoked here rather than on the server. Without one they
// read anonymously, sixty requests an hour.
export function GithubToken({ residentName, status, onStore, onRevoke }: GithubTokenProps) {
  const [token, setToken] = useState('');
  const [confirming, setConfirming] = useState(false);
  return (
    <Card title="GitHub">
      <p style={{ margin: 0, fontSize: 15 }}>
        {status.present
          ? `A read token is stored since ${status.stored_at?.slice(0, 10)}; ${residentName}'s pull request reads use it.`
          : `No token: ${residentName} reads pull requests anonymously, sixty requests an hour (about twenty pr_meta reads).`}
      </p>
      <p style={{ margin: 0, fontSize: 13, color: 'var(--ink-muted)' }}>
        A fine-grained token with read-only access to the repository is enough. It is stored encrypted and never shown again.
      </p>
      <form
        aria-label="GitHub token"
        onSubmit={(event) => {
          event.preventDefault();
          if (token.trim()) onStore(token.trim());
          setToken('');
        }}
        style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' }}
      >
        <Field label={status.present ? 'Replace the token' : 'Paste a token'} type="password" value={token} onChange={(e) => setToken(e.target.value)} />
        <Button variant="primary" type="submit" disabled={token.trim() === ''}>
          {status.present ? 'Replace' : 'Store'}
        </Button>
        {status.present ? (
          <Button variant="quiet" type="button" onClick={() => (confirming ? onRevoke() : setConfirming(true))} onBlur={() => setConfirming(false)}>
            {confirming ? 'Revoke the token' : 'Revoke'}
          </Button>
        ) : null}
      </form>
    </Card>
  );
}
