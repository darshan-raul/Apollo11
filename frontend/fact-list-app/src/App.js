// App.js
import React, { useState, useEffect } from 'react';
import 'bootstrap/dist/css/bootstrap.min.css';
import axios from 'axios';

function App() {
  const [facts, setFacts] = useState([]);
  const [newFact, setNewFact] = useState('');

  useEffect(() => {
    fetchFacts();
  }, []);

  const fetchFacts = async () => {
    try {
      const response = await axios.get('http://localhost:8080/facts');
      setFacts(response.data);
    } catch (error) {
      console.error('Error fetching facts:', error);
    }
  };

  const addFact = async () => {
    if (newFact.trim() === '') return;
    try {
      await axios.post('http://localhost:8080/facts', { text: newFact });
      setNewFact('');
      fetchFacts();
    } catch (error) {
      console.error('Error adding fact:', error);
    }
  };

  return (
    <div className="container">
      <header className="bg-primary text-white p-4 mb-4">
        <h1>Apollo 11 Facts</h1>
      </header>
      <div className="row">
        <div className="col-md-6">
          <h2>Fact List</h2>
          <ul className="list-group">
            {facts.map(fact => (
              <li key={fact.id} className="list-group-item">{fact.text}</li>
            ))}
          </ul>
        </div>
        <div className="col-md-6">
          <h2>Add New Fact</h2>
          <div className="input-group mb-3">
            <input
              type="text"
              className="form-control"
              placeholder="Enter a new fact"
              value={newFact}
              onChange={(e) => setNewFact(e.target.value)}
            />
            <button className="btn btn-primary" onClick={addFact}>Add Fact</button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;