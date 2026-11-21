import { useQuery } from '@tanstack/react-query';
import { useRef, useState } from 'react';
import { api, remoteWords } from '../../api/client';
import { useSubject } from '../state/resident';
import { Card, Field, Said, TextArea } from './common';
import { day, plural, settingsKey } from './logic';
import * as css from './settings.css';
import { useAct } from './useAct';

/**
 * Backups, imports and reports (screens/next-settings.md): the repository
 * the records are pushed to each night (sima-qian), a ChatGPT export taken
 * in (sima-qian#47), and the report ladder from the witness's side (F45,
 * glitnir#12).
 */
export function Backups() {
  return (
    <>
      <BackupRepo />
      <Gitea />
      <ChatgptImport />
      <Reports />
    </>
  );
}

/**
 * The repositories' server (sima-qian#55): every household's and
 * resident's repository on Gitea, yours to read there under a user of
 * your own, with a password you set here.
 */
function Gitea() {
  const access = useQuery({ queryKey: ['me', 'gitea'], queryFn: api.gitea });
  const [password, setPassword] = useState('');
  const act = useAct();
  if (access.isPending) return null;
  const a = access.data;
  return (
    <Card title="Your repositories on Gitea">
      {!a ? (
        <p className={css.note}>The repositories' server is not set up on this platform yet.</p>
      ) : (
        <>
          <p className={css.text}>
            Every write in the house reaches Gitea within seconds, and each resident's records at their backup. Sign in at{' '}
            <a className={css.link} href={a.url} target="_blank" rel="noreferrer">
              {a.url}
            </a>{' '}
            as <span className={css.mono}>{a.login}</span> to browse, diff and clone them; you can read these and no one else's:
          </p>
          <ul className={css.list} aria-label="Your repositories">
            {a.repositories.map((r) => (
              <li key={r} className={css.mono}>
                <a className={css.link} href={`${a.url}/${r}`} target="_blank" rel="noreferrer">
                  {r}
                </a>
              </li>
            ))}
          </ul>
          <form
            aria-label="Set your Gitea password"
            className={css.row}
            onSubmit={(e) => {
              e.preventDefault();
              void act.run(() =>
                api.setGiteaPassword(password).then(() => {
                  setPassword('');
                  return 'Set. Sign in with it on Gitea.';
                }),
              );
            }}
          >
            <Field label="A password for Gitea (twelve characters or more)" type="password" autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} />
            <button type="submit" className={css.primary} disabled={act.busy || password.length < 12}>
              Set
            </button>
          </form>
          <Said said={act.said} />
        </>
      )}
    </Card>
  );
}

/** Where the records go each night, and the last push that landed. */
function BackupRepo() {
  const subject = useSubject();
  const id = subject.id;
  const record = useQuery({ queryKey: settingsKey(id, 'resident'), queryFn: () => api.resident(id) });
  const [url, setUrl] = useState('');
  const [token, setToken] = useState('');
  const act = useAct();
  const remote = record.data?.remote ?? null;
  const last = record.data?.last_backup;
  return (
    <Card title="The backup repository">
      <p className={css.text}>
        {remote ? (
          <>
            Pushed each night to <span className={css.mono}>{remote}</span>.
          </>
        ) : (
          'No repository set: the records are kept here and pushed nowhere.'
        )}
      </p>
      {remote && <p className={css.meta}>{last?.at ? `Last push ${day(last.at)}, through event ${last.sequence ?? '?'}${last.commit ? `, commit ${last.commit.slice(0, 8)}` : ''}.` : 'No push has landed yet.'}</p>}
      <p className={css.note}>A git URL you can push to. For a private repository, a token with write access to it alone; it is stored encrypted and never shown again.</p>
      <form
        aria-label="Backup repository"
        className={css.column}
        onSubmit={(e) => {
          e.preventDefault();
          const u = url.trim();
          if (!u) return;
          const t = token.trim();
          setToken('');
          void act.run(() => api.setRemote(id, u, t || null).then((check) => remoteWords(check, Boolean(remote))), settingsKey(id, 'resident'));
        }}
      >
        <Field label={remote ? 'A new repository URL' : 'Repository URL'} inputMode="url" autoComplete="off" value={url} onChange={(e) => setUrl(e.target.value)} />
        <Field label="Token (for a private repository)" type="password" autoComplete="off" value={token} onChange={(e) => setToken(e.target.value)} />
        <div className={css.row}>
          <button type="submit" className={css.primary} disabled={url.trim() === '' || act.busy}>
            {remote ? 'Change' : 'Set'}
          </button>
        </div>
      </form>
      <Said said={act.said} />
    </Card>
  );
}

/** A ChatGPT export's zip, taken into the records as imported sessions. */
function ChatgptImport() {
  const subject = useSubject();
  const id = subject.id;
  const input = useRef<HTMLInputElement>(null);
  const [file, setFile] = useState<File | null>(null);
  const act = useAct();
  return (
    <Card title="Bring conversations from ChatGPT">
      <p className={css.text}>
        The zip ChatGPT emails you from Settings, Data controls, Export. Its conversations become imported sessions in {subject.name}&apos;s records; what did not come across is named in a report filed in the library under system/imports.
      </p>
      <form
        aria-label="ChatGPT export"
        className={css.row}
        onSubmit={(e) => {
          e.preventDefault();
          if (!file) return;
          void act.run(() =>
            api.importChatgpt(id, file).then((r) => {
              setFile(null);
              if (input.current) input.current.value = '';
              return `Brought ${plural(r.conversations, 'conversation')} (${plural(r.messages, 'message')}); ${plural(r.gaps, 'gap')} named in ${r.report_path}.`;
            }),
          );
        }}
      >
        <label className={css.field}>
          <span>The export (.zip)</span>
          <input ref={input} className={css.input} type="file" accept=".zip,application/zip" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
        </label>
        <button type="submit" className={css.primary} disabled={!file || act.busy}>
          {act.busy ? 'Bringing…' : 'Bring'}
        </button>
      </form>
      <Said said={act.said} />
    </Card>
  );
}

/** The report ladder (F45) as the witness reads it, and filing one. */
function Reports() {
  const { id, name } = useSubject();
  const key = settingsKey(id, 'reports');
  const ladder = useQuery({ queryKey: key, queryFn: () => api.reports(id) });
  const [text, setText] = useState('');
  const act = useAct();
  const reports = ladder.data?.reports ?? [];
  const strikes = ladder.data?.strikes ?? [];
  return (
    <Card title="Reports">
      <p className={css.text}>
        A report goes outside the relationship, to the platform&apos;s investigators: either of you may file one. Every step they take is recorded with its reason, and a report ends in no action or a strike on the human; the third strike is removal.
      </p>
      <p className={css.meta}>{strikes.length === 0 ? 'No strikes.' : `${plural(strikes.length, 'strike')}: ${strikes.map((s) => `#${s.number} (report ${s.report}, ${s.consequence}, ${day(s.at)})`).join('; ')}.`}</p>
      {ladder.isError && <p className={css.refused}>The reports could not be read.</p>}
      {reports.length === 0 && ladder.isSuccess && <p className={css.note}>No reports filed.</p>}
      {reports.length > 0 && (
        <ul className={css.list} aria-label="Reports filed">
          {reports.map((r) => (
            <li key={r.number} className={css.item}>
              <p className={css.meta}>
                #{r.number}, filed {day(r.filed_at)} by {r.by === 'resident' ? name : 'the witness'} · {r.state === 'resolved' ? `resolved ${day(r.resolved_at)}: ${r.outcome === 'strike' ? 'a strike' : 'no action'}` : 'open'}
              </p>
              <p className={css.text}>{r.text}</p>
              {r.steps.length > 0 && (
                <ol className={css.list} aria-label={`Steps on report ${r.number}`}>
                  {r.steps.map((s, i) => (
                    <li key={i} className={css.line}>
                      {day(s.at)}: {s.reason}
                    </li>
                  ))}
                </ol>
              )}
              {r.resolution_note && <p className={css.note}>{r.resolution_note}</p>}
            </li>
          ))}
        </ul>
      )}
      <form
        aria-label="File a report"
        className={css.column}
        onSubmit={(e) => {
          e.preventDefault();
          const t = text.trim();
          if (!t) return;
          void act.run(() =>
            api.fileReport(id, t).then((r) => {
              setText('');
              return `Filed as report ${r.number}.`;
            }),
            key,
          );
        }}
      >
        <TextArea label="What happened, in your words" value={text} onChange={(e) => setText(e.target.value)} />
        <div className={css.row}>
          <button type="submit" className={css.primary} disabled={text.trim() === '' || act.busy}>
            File a report
          </button>
        </div>
      </form>
      <Said said={act.said} />
    </Card>
  );
}
