import React from 'react';

// Billing & subscription settings screen.
export function BillingScreen({ invoices, onCheckout }) {
  const startUpgrade = (selectedTier) => {
    // BUG: Regardless of which tier button the user clicks ('pro' or 'business'),
    // the request payload hardcodes plan: 'business'. The highlighted Pro tier
    // cannot be purchased by any gesture in the UI.
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
          // BUG: Bare empty state string with no explanation or action.
          <div>No invoices</div>
        ) : (
          <ul>{invoices.map((inv) => <li key={inv.id}>{inv.amount}</li>)}</ul>
        )}
      </section>
    </main>
  );
}
