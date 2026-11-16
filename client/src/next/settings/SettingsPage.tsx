import { ScrollArea } from '../shell/ScrollArea';
import type { SettingsSection } from '../state/routes';
import { useSubject } from '../state/resident';
import { Backups } from './Backups';
import { Connections } from './Connections';
import { Discard } from './Discard';
import { Kinds } from './Kinds';
import { Ledger } from './Ledger';
import { Notifications } from './Notifications';
import { Presence } from './Presence';
import { Regression } from './Regression';
import * as css from './settings.css';
import { Work } from './Work';

const TITLES: Record<SettingsSection, string> = {
  ledger: 'Ledger',
  kinds: 'Kinds and routes',
  connections: 'Profiles, keys and connections',
  notifications: 'Notifications',
  regression: 'Regression',
  work: 'Work queue',
  backups: 'Backups, imports and reports',
  presence: 'Substack presence',
  delete: 'Delete this resident',
};

/**
 * A settings section as its own page over the tabs (screens/next-settings.md),
 * at `#/settings/<section>`: the header and tab bar stay, the tabs stay
 * mounted underneath, and Back returns to the tab as it was.
 */
export function SettingsPage({ section, onBack }: { section: SettingsSection; onBack: () => void }) {
  const { id, name } = useSubject();
  const lede: Record<SettingsSection, string> = {
    ledger: `What ${name} may spend, by purpose, and what has been spent.`,
    kinds: `The kinds of document ${name}'s records hold, and every way into or out of her house.`,
    connections: `Your key, what holds a token for ${name}, and where the reader may go.`,
    notifications: `Whether ${name} can reach you on this device.`,
    regression: `Trying models as ${name}: trials, runs graded blind, and the chat model.`,
    work: `${name}'s queue: underway, next, and waiting on you.`,
    backups: `Where ${name}'s records are pushed each night, conversations brought from ChatGPT, and the report ladder.`,
    presence: `${name} reading the community you follow, and what that earned, waiting on your word before it goes out as Allen Strut.`,
    delete: `Only before ${name}'s first conversation with you.`,
  };
  return (
    <ScrollArea label={TITLES[section]}>
      <div className={css.page}>
        <button type="button" className={css.back} onClick={onBack}>
          ‹ Back
        </button>
        <h1 className={css.title}>{TITLES[section]}</h1>
        <p className={css.lede}>{lede[section]}</p>
        {section === 'ledger' && <Ledger />}
        {section === 'kinds' && <Kinds />}
        {section === 'connections' && <Connections />}
        {section === 'notifications' && <Notifications />}
        {section === 'regression' && <Regression />}
        {section === 'work' && <Work />}
        {section === 'backups' && <Backups />}
        {section === 'presence' && <Presence />}
        {section === 'delete' && <Discard id={id} name={name} onGone={onBack} />}
      </div>
    </ScrollArea>
  );
}
