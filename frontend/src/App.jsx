import React, { useEffect, useState } from 'react';

export default function App() {
  const [items, setItems] = useState([]);
  const [name, setName] = useState('');
  const [health, setHealth] = useState('checking...');
  const [error, setError] = useState(null);

  const loadItems = async () => {
    try {
      const res = await fetch('/api/items');
      if (!res.ok) throw new Error(`Backend returned ${res.status}`);
      setItems(await res.json());
      setError(null);
    } catch (err) {
      setError(err.message);
    }
  };

  const checkHealth = async () => {
    try {
      const res = await fetch('/api/health');
      setHealth(res.ok ? 'ok' : `error (${res.status})`);
    } catch {
      setHealth('unreachable');
    }
  };

  useEffect(() => {
    loadItems();
    checkHealth();
  }, []);

  const addItem = async (e) => {
    e.preventDefault();
    if (!name.trim()) return;
    try {
      const res = await fetch('/api/items', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name }),
      });
      if (!res.ok) throw new Error(`Backend returned ${res.status}`);
      setName('');
      loadItems();
    } catch (err) {
      setError(err.message);
    }
  };

  return (
    <div style={{ fontFamily: 'sans-serif', maxWidth: 520, margin: '40px auto' }}>
      <h1>DevOps Task Demo</h1>
      <p>
        Backend health: <strong>{health}</strong>
      </p>

      <form onSubmit={addItem} style={{ display: 'flex', gap: 8, marginBottom: 16 }}>
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="New item name"
          style={{ flex: 1, padding: 8 }}
        />
        <button type="submit" style={{ padding: '8px 16px' }}>
          Add
        </button>
      </form>

      {error && <p style={{ color: 'red' }}>Error: {error}</p>}

      <h2>Items from database</h2>
      <ul>
        {items.map((item) => (
          <li key={item.id}>
            {item.name} — {new Date(item.created_at).toLocaleString()}
          </li>
        ))}
      </ul>
      {items.length === 0 && !error && <p>No items yet — add one above.</p>}
    </div>
  );
}
