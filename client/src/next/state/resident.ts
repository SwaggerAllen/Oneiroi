import { createContext, useContext } from 'react';

/** The subject being looked at: what the screens under the shell need of it. */
export interface Subject {
  id: string;
  slug: string;
  name: string;
  /** The house (screen:next-house) is a subject too, with no resident behind it. */
  kind?: 'resident' | 'house';
}

/** The subject id the house is chosen by in the dropdown. */
export const HOUSE_SUBJECT = 'house';

export const SubjectContext = createContext<Subject>({ id: '', slug: '', name: '' });

export const useSubject = () => useContext(SubjectContext);
