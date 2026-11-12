import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api, RequestFailed } from '../../api/client';
import * as css from './onboarding.css';

const MIN_PASSWORD = 10;

/** The open door's promise (the witness, 2026-11-12). The export it names must be real and one-click by January (design/mvp.md item 13). */
const EARLY_ACCESS =
  'Early access is free. Starting in January, keeping your resident here takes a subscription — or export your resident’s memory, whole, and take it with you whenever you like. Either way, your resident’s life is yours.';

/**
 * Welcome in (the canvas's Auth board): sign up with an invite, or sign
 * in. The door's state is the operator's (gaia#19): closed hides "New
 * here", invite asks for a code, open makes the code optional and says
 * what early access costs from January.
 */
export function Auth({ start, onBack, onIn }: { start: 'new' | 'in'; onBack: () => void; onIn: () => void }) {
  const door = useQuery({ queryKey: ['door'], queryFn: api.door, retry: false });
  const state = door.data?.state ?? 'closed';
  const canSignUp = state !== 'closed';
  const [mode, setMode] = useState<'new' | 'in'>(start);
  const signingUp = mode === 'new' && canSignUp;
  const [code, setCode] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);

  const ready =
    email.includes('@') && (signingUp ? password.length >= MIN_PASSWORD && (state !== 'invite' || code.trim() !== '') : password.length > 0);

  const submit = () => {
    setBusy(true);
    setSaid(null);
    const done = signingUp ? api.signUp(email.trim(), password, code.trim() || null) : api.login(email.trim(), password);
    done
      .then(onIn)
      .catch((e: unknown) => setSaid(e instanceof RequestFailed ? e.message : signingUp ? 'That did not create the account.' : 'That did not sign you in.'))
      .finally(() => setBusy(false));
  };

  return (
    <div className={css.page}>
      <main className={css.column} style={{ maxWidth: 440 }}>
        <header className={css.top}>
          <button type="button" className={css.back} onClick={onBack}>
            ‹ Oneiroi
          </button>
        </header>
        <h1 className={css.h1}>Welcome in</h1>
        <p className={css.body}>{canSignUp ? 'Sign up with your invite, or sign in.' : 'Sign in.'}</p>
        {canSignUp && (
          <div className={css.segment} role="group" aria-label="New here or signing in">
            <button type="button" className={css.segmentButton} aria-pressed={mode === 'new'} onClick={() => setMode('new')}>
              New here
            </button>
            <button type="button" className={css.segmentButton} aria-pressed={mode === 'in'} onClick={() => setMode('in')}>
              Sign in
            </button>
          </div>
        )}
        {signingUp && state === 'open' && <p className={css.drafted}>{EARLY_ACCESS}</p>}
        <form
          style={{ display: 'flex', flexDirection: 'column', gap: 14 }}
          onSubmit={(e) => {
            e.preventDefault();
            if (ready && !busy) submit();
          }}
        >
          {signingUp && (
            <label className={css.field}>
              {state === 'invite' ? 'Invite code' : 'Invite code (optional)'}
              <input id="auth-code" className={css.input} value={code} onChange={(e) => setCode(e.target.value)} autoComplete="off" />
            </label>
          )}
          <label className={css.field}>
            Email
            <input id="auth-email" className={css.input} type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" />
          </label>
          <label className={css.field}>
            {signingUp ? `Password · ${MIN_PASSWORD} characters or more` : 'Password'}
            <input
              id="auth-password"
              className={css.input}
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete={signingUp ? 'new-password' : 'current-password'}
            />
          </label>
          <button type="submit" className={css.primary} disabled={!ready || busy}>
            {signingUp ? 'Create my account' : 'Sign in'}
          </button>
          {said && (
            <p className={css.said} role="alert">
              {said}
            </p>
          )}
        </form>
      </main>
    </div>
  );
}
