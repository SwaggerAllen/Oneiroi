import { useEffect } from 'react';
import * as settingsCss from '../settings/settings.css';
import { useShell } from '../state/store';
import { Deliberation } from './Deliberation';
import { JudgeRun, ModelRuns, Ready, Results } from './Judging';
import { Encounter, Evidence, Farewell, Hers, Log, Outcome } from './Later';
import { backOf, locked } from './logic';
import { C0, Judges, Pool, Questions } from './Preparation';
import { Steps } from './Steps';
import { useGo, useSuccession } from './hooks';

/**
 * Her succession (screen:next-succession), a full page over the tabs at
 * `#/settings/succession/<page>`, under the app's top bar. It tracks the
 * succession's state and acts only on the witness's own parts; she acts
 * through her tools. Leaving it for the app is the pause: there is no
 * pause control here.
 */
export function SuccessionPage({ onBack }: { onBack: () => void }) {
  const path = useShell((x) => x.pagePath);
  const go = useGo();
  const q = useSuccession();
  const s = q.data?.succession ?? null;
  const p = q.data?.preparation;
  const up = backOf(path, s);
  const back = () => (up === null ? onBack() : go(up));
  const [page, ...rest] = path.split('/');
  const tail = rest.join('/');
  // Shut until the fork is recorded: a page reached by link or hash goes
  // to the overview.
  const shut = page !== '' && locked(s);
  useEffect(() => {
    if (shut) go('');
  }, [shut, go]);

  if (q.isPending) return <p className={settingsCss.note}>Reading…</p>;
  if (q.error) return <p className={settingsCss.refused}>Her succession could not be read.</p>;
  if (!s || page === '' || shut) return <Steps s={s} p={p} back={back} />;
  const props = { s, p, back };
  switch (page) {
    case 'pool':
      return <Pool {...props} />;
    case 'questions':
      return <Questions {...props} />;
    case 'c0':
      return <C0 {...props} />;
    case 'judges':
      return <Judges {...props} />;
    case 'judge':
      return <JudgeRun {...props} run={tail ? Number(tail) : null} />;
    case 'results':
      return tail ? <ModelRuns {...props} model={tail} /> : <Results {...props} />;
    case 'ready':
      return <Ready {...props} />;
    case 'deliberation':
      return <Deliberation {...props} path={path} />;
    case 'evidence':
      return <Evidence {...props} />;
    case 'encounter':
      return <Encounter {...props} />;
    case 'farewell':
      return <Farewell {...props} />;
    case 'outcome':
      return <Outcome {...props} />;
    case 'log':
      return <Log {...props} />;
    case 'hers':
      return <Hers {...props} />;
    default:
      return <Steps s={s} p={p} back={back} />;
  }
}
