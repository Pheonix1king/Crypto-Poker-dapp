import React from "react";

function PokerTable({ playerCards, communityCards }) {
  return (
    <div style={{ textAlign: "center", marginTop: "20px" }}>
      <h2>Community Cards</h2>
      <div>{communityCards.map((card, i) => <span key={i}>{card.value}{card.suit} </span>)}</div>

      <h2>Your Cards</h2>
      <div>{playerCards.map((card, i) => <span key={i}>{card.value}{card.suit} </span>)}</div>
    </div>
  );
}

export default PokerTable;
