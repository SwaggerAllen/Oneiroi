import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type PlatformRole } from '../../api/client';
import { ROLE_NAMES } from './logic';
import { Card, Field, RevokeWithNote, SaidLine } from './parts';
import { useOp } from './useOp';
import * as css from './operator.css';

const KEY = ['operator', 'platform'];

/**
 * The platform roles (gaia#16): who holds which, granted by email and
 * revoked, each with a recorded note. The server checks the authority
 * again on each change and refuses revoking the last super admin.
 */
export function Roles() {
  const platform = useQuery({ queryKey: KEY, queryFn: api.platform });
  const op = useOp();
  const [email, setEmail] = useState('');
  const [role, setRole] = useState<PlatformRole>('admin');
  const [note, setNote] = useState('');
  const ready = email.trim() !== '' && note.trim() !== '';
  const roles = platform.data?.roles ?? [];
  return (
    <>
      <Card title={`ROLES · ${roles.length}`} label="Platform roles">
        {roles.map((r) => (
          <div key={`${r.account_id}-${r.role}`} className={css.row}>
            <span className={css.stack}>
              <span>
                {r.email ?? r.account_id} · {ROLE_NAMES[r.role]}
              </span>
              <span className={css.mono}>
                since {r.granted_at.slice(0, 10)}
                {r.note ? ` · ${r.note}` : ''}
              </span>
            </span>
            <RevokeWithNote
              what={`${ROLE_NAMES[r.role]} from ${r.email ?? r.account_id}`}
              busy={op.busy}
              onRevoke={(n) => op.run(() => api.revokeRole(r.account_id, r.role, n).then(() => `Revoked ${ROLE_NAMES[r.role]} from ${r.email ?? r.account_id}.`), KEY)}
            />
          </div>
        ))}
        <SaidLine said={op.said} />
      </Card>
      <section className={css.card} aria-label="Grant a role">
        <h2 className={css.heading}>GRANT A ROLE</h2>
        <form
          className={css.form}
          onSubmit={(e) => {
            e.preventDefault();
            if (!ready) return;
            const to = email.trim();
            void op
              .run(() => api.grantRole(to, role, note.trim()).then(() => `Granted ${ROLE_NAMES[role]} to ${to}.`), KEY)
              .then((ok) => {
                if (!ok) return;
                setEmail('');
                setNote('');
              });
          }}
        >
          <div className={css.grid}>
            <Field label="Account email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
            <label className={css.field}>
              <span>Role</span>
              <select className={css.input} value={role} onChange={(e) => setRole(e.target.value as PlatformRole)}>
                <option value="admin">Admin</option>
                <option value="super_admin">Super admin</option>
              </select>
            </label>
          </div>
          <Field label="Why (recorded with the grant)" value={note} onChange={(e) => setNote(e.target.value)} />
          <div className={css.buttons}>
            <button type="submit" className={css.primary} disabled={op.busy || !ready}>
              Grant
            </button>
          </div>
        </form>
        <p className={css.note}>A transfer of the operator is a grant of super admin, then a revoke of your own; the last super admin can't be revoked.</p>
      </section>
    </>
  );
}
