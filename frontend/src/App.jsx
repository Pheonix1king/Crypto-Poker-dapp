import { useState } from "react";
import { ethers } from "ethers";
import contractABI from "./utils/contractABI.json";

function App() {
  const [account, setAccount] = useState("");

  async function connectWallet() {
    if (window.ethereum) {
      const accounts = await window.ethereum.request({ method: "eth_requestAccounts" });
      setAccount(accounts[0]);
    }
  }

  return (
    <div style={{ padding: "20px" }}>
      <h1>Crypto Poker DApp</h1>
      {!account ? (
        <button onClick={connectWallet}>Connect Wallet</button>
      ) : (
        <p>Connected: {account}</p>
      )}
    </div>
  );
}

export default App;
