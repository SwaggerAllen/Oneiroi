import { createContext, useContext } from 'react';

/** The subject being looked at: what the screens under the shell need of it. */
export interface Subject {
  id: string;
  slug: string;
  name: string;
}

export const SubjectContext = createContext<Subject>({ id: '', slug: '', name: '' });

export const useSubject = () => useContext(SubjectContext);
