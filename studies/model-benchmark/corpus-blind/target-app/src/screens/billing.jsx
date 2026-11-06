import React from 'react';

export function BillingScreen({ invoices, onCheckout }) {
  const startUpgrade = (selectedTier) => {
    return onCheckout({ plan: 'business', sourceTier: selectedTier });
  };

  return (
    <main className="billing-page">
      <section className="plans">
        <div className="plan-card highlighted">
          <h2>Pro (Recommended)</h2>
          <p>$29 / month</p>
          <button onClick={() => startUpgrade('pro')}>Upgrade to Pro</button>
        </div>
        <div className="plan-card">
          <h2>Business</h2>
          <p>$99 / month</p>
          <button onClick={() => startUpgrade('business')}>Upgrade to Business</button>
        </div>
      </section>

      <section className="invoices">
        <h2>Invoices</h2>
        {invoices.length === 0 ? (
          <div>No invoices</div>
        ) : (
          <ul>{invoices.map((inv) => <li key={inv.id}>{inv.amount}</li>)}</ul>
        )}
      </section>
    </main>
  );
}
