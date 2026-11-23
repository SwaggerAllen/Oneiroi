import { QueryClient } from '@tanstack/react-query';

/** The app's one query client: here, so a subject switch can wait on what the new view reads. */
export const queries = new QueryClient({
  defaultOptions: { queries: { staleTime: 60_000, refetchOnWindowFocus: false, retry: 1 } },
});
