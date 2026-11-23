/**
 * A tiny stand-in for the Supabase client used by route tests.
 * Every query is recorded as { table, ops: [[method, ...args], ...] } and
 * answered by the `respond` function you pass in.
 */
export function fakeSupabase(respond = () => ({ data: null, error: null })) {
  const calls = [];

  const builder = (table) => {
    const record = { table, ops: [] };
    calls.push(record);
    const proxy = new Proxy(
      {},
      {
        get(_, prop) {
          if (prop === 'then') {
            const result = Promise.resolve(respond(record));
            return result.then.bind(result);
          }
          return (...args) => {
            record.ops.push([prop, ...args]);
            return proxy;
          };
        },
      },
    );
    return proxy;
  };

  return {
    calls,
    from: (table) => builder(table),
    rpc: (fn, args) => {
      const record = { table: `rpc:${fn}`, ops: [['rpc', args]] };
      calls.push(record);
      return Promise.resolve(respond(record));
    },
    storage: {
      from: (bucket) => ({
        upload: async (path) => respond({ table: `storage:${bucket}`, ops: [['upload', path]] }),
        remove: async (paths) => respond({ table: `storage:${bucket}`, ops: [['remove', paths]] }),
        list: async () => ({ data: [], error: null }),
        createSignedUrl: async (path) => ({ data: { signedUrl: `https://signed/${path}` }, error: null }),
        getPublicUrl: (path) => ({ data: { publicUrl: `https://public/${bucket}/${path}` } }),
      }),
    },
  };
}

export const has = (record, method) => record.ops.find(([m]) => m === method);
