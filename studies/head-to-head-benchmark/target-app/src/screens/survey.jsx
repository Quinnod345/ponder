import React from 'react';

// Participant survey screen reached via emailed magic link (/survey/:hash).
export function SurveyScreen({ companyName, questions, onSubmit }) {
  return (
    <main className="survey-page">
      <header>
        <h1>{companyName} Team Checkup</h1>
        <p className="privacy-promise">
          Your individual answers stay private: nobody at {companyName} sees what you
          answered. Leadership only sees one combined reading once at least 3 teammates
          have completed the checkup.
        </p>
      </header>
      <form onSubmit={onSubmit}>
        {questions.map((q) => (
          <fieldset key={q.id}>
            <legend>{q.prompt}</legend>
            <input type="number" min="1" max="5" name={`q_${q.id}`} required />
          </fieldset>
        ))}
        <button type="submit">Submit Checkup</button>
      </form>
    </main>
  );
}
