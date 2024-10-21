# Pepper Prediction Market Protocol White Paper

## Table of Contents

- [Pepper Gambling Protocol White Paper](#pepper-gambling-protocol-white-paper)
  - [Table of Contents](#table-of-contents)
  - [1. Introduction](#1-introduction)
  - [2. Protocol Overview](#2-protocol-overview)
    - [2.1 Key Features](#21-key-features)
  - [3. Mathematical Model](#3-mathematical-model)
    - [3.1 Betting Mechanics](#31-betting-mechanics)
    - [3.2 Odds Calculation](#32-odds-calculation)
    - [3.3 Payout Distribution](#33-payout-distribution)
    - [3.4 Protocol Fees](#34-protocol-fees)
  - [4. Protocol Architecture](#4-protocol-architecture)
    - [4.1 Event Lifecycle](#41-event-lifecycle)
    - [4.2 Betting Pools](#42-betting-pools)
    - [4.3 Fee Structure](#43-fee-structure)
    - [4.4 Token Support](#44-token-support)
  - [5. Smart Contract Design](#5-smart-contract-design)
    - [5.1 Contract Overview](#51-contract-overview)
    - [5.2 Event Factory Contract](#52-event-factory-contract)
    - [5.3 Event Contract](#53-event-contract)
    - [5.4 Collateral Management](#54-collateral-management)
  - [6. Oracle Integration](#6-oracle-integration)
    - [6.1 Event Resolution](#61-event-resolution)
    - [6.2 Dispute Resolution Mechanism](#62-dispute-resolution-mechanism)
  - [7. Governance](#7-governance)
    - [7.1 Protocol Governance](#71-protocol-governance)
    - [7.2 Event Creator Governance](#72-event-creator-governance)
  - [8. Security Considerations](#8-security-considerations)
    - [8.1 Smart Contract Security](#81-smart-contract-security)
    - [8.2 Economic Security](#82-economic-security)
    - [8.3 Regulatory Compliance](#83-regulatory-compliance)
  - [9. Implementation Details](#9-implementation-details)
    - [9.1 Blockchain Platform](#91-blockchain-platform)
    - [9.2 User Interface](#92-user-interface)
    - [9.3 Wallet Integration](#93-wallet-integration)
  - [10. Conclusion](#10-conclusion)
  - [11. References](#11-references)
  - [12. Disclaimer](#12-disclaimer)

---

## 1. Introduction

The Pepper Gambling Protocol is a decentralized, non-custodial platform facilitating peer-to-peer betting on various events, including sports, politics, and other verifiable occurrences. Built on blockchain technology, Pepper offers a transparent and trustless environment where users can create events, place bets, and resolve outcomes without intermediaries. The protocol enhances capital efficiency by aggregating liquidity and provides fair odds based on the distribution of bets on each side of an event.

---

## 2. Protocol Overview

### 2.1 Key Features

- **Decentralized Event Creation**: Any user can create events by providing collateral, making the platform open and decentralized.
- **Collateral-Based Betting Limits**: The event creator's collateral sets the maximum total stake allowed on the event.
- **Event Creator as Oracle**: The event creator acts as the oracle and is responsible for providing the outcome to the contract.
- **Multi-Outcome Support**: Supports events with multiple possible outcomes.
- **Dynamic Odds Calculation**: Odds are calculated based on the total amount wagered on each outcome, adjusting in real-time.
- **Fair Payout Distribution**: The total amount staked on losing outcomes is redistributed among winners proportionally.
- **Protocol Fees**: A 10% fee is charged on the total loot (losing bets), split equally between the event creator and the protocol.
- **Security and Transparency**: Smart contracts govern all operations, and mechanisms are in place to handle disputes and ensure fair outcomes.

---

## 3. Mathematical Model

### 3.1 Betting Mechanics

Consider an event $\( E \)$ with $\( n \)$ possible outcomes:

- Outcomes: $\( O_1, O_2, ..., O_n \)$

Let:

- $\( S_i \$) = Total amount staked on outcome $\( O_i \)$
- $\( s_{i,j} \)$ = Amount staked by user $\( j \)$ on outcome $\( O_i \)$
- $\( C \)$ = Collateral provided by the event creator
- **Betting Limit**: The total amount staked across all outcomes cannot exceed $\( L_{\text{max}} = C \times m \)$, where $\( m \)$ is a multiplier determined by the protocol.

### 3.2 Odds Calculation

The odds for each outcome $\( O_i \)$ are calculated based on the total amounts staked on all other outcomes:
```math
 {Odds}_{O_i} = \frac{\sum_{k \neq i} S_k}{S_i}
```

These odds represent the potential return on each unit staked if outcome $\( O_i \)$ wins.

**Example**:

- Event with three outcomes: $\( O_1 \), \( O_2 \), \( O_3 \)$
- Total staked:
  - $` S_1 = \$500,000 `$
  - $` S_2 = \$300,000`$
  - $` S_3 = \$200,000 `$

Calculating the odds:

- Odds for $\( O_1 \)$:
```math
  {Odds}_{O_1} = \frac{\$300,000 + \$200,000}{\$500,000} = \frac{\$500,000}{\$500,000} = 1
```
- Odds for $\( O_2 \)$:
```math
  {Odds}_{O_2} = \frac{\$500,000 + \$200,000}{\$300,000} \approx 2.33
```
- Odds for $\( O_3 \)$:
```math
  {Odds}_{O_3} = \frac{\$500,000 + \$300,000}{\$200,000} = \frac{\$800,000}{\$200,000} = 4
```

### 3.3 Payout Distribution

Upon event resolution:

- **Total Loot $\( L \)$**:
```math
  L = \sum_{i \neq w} S_i
```
  where $\( w \)$ is the index of the winning outcome.

- **Protocol Fee $\( F \)$**:
```math
  F = L \times f
```
  where $\( f = 1\% \)$ is the protocol fee.

- **Net Loot After Fee $\( L_{\text{net}} \)$**:
```math
  L_{\text{net}} = L - F
```

- **Fee Distribution**:
  - **Event Creator Fee $\ F_c \$**:
```math
    F_c = \frac{F}{2}
```
  - **Protocol Fee $\( F_p \)$**:
```math
    F_p = \frac{F}{2}
```

- **User Payout $\( P_{w,j} \)$** for user $\( j \)$ who bet on the winning outcome:
```math
  P_{w,j} = s_{w,j} + \left( \frac{s_{w,j}}{S_w} \times L_{\text{net}} \right)
```

**Example Continued**:

- Winning Outcome: $\( O_2 \)$
- **Total Loot**:
```math
  L = S_1 + S_3 = \$500,000 + \$200,000 = \$700,000
```
- **Protocol Fee**:
```math
  F = \$700,000 \times 1\% = \$7,000
```
- **Net Loot**:
```math
  L_{\text{net}} = \$700,000 - \$7,000 = \$693,000
```
- **Fee Distribution**:
  - $` F_c = \$3,500 `$
  - $` F_p = \$3,500 `$
- **User's Share**:
  - User $\( j \)$ bets $` s_{2,j} = \$100,000 `$
  - Total winning stake $` S_2 = \$300,000 `$
  - User $\( j \)$'s payout:
```math
    P_{2,j} = \$100,000 + \left( \frac{\$100,000}{\$300,000} \times \$693,000 \right) = \$100,000 + \$231,000 = \$331,000
```

### 3.4 Protocol Fees

- **Total Fee**:
```math
  F = L \times f
```
- **Fee Split**:
  - **Event Creator**:
```math
    F_c = \frac{F}{2}
```
  - **Protocol**:
```math
    F_p = \frac{F}{2}
```

---

## 4. Protocol Architecture

### 4.1 Event Lifecycle

1. **Event Creation**:
   - Any user can create an event by providing collateral $\( C \)$.
   - The collateral sets the maximum total stake $\( L_{\text{max}} \)$ allowed on the event.

2. **Betting Phase**:
   - Users place bets on the available outcomes.
   - Bets are accepted until the event's start time or when $\( L_{\text{max}} \)$ is reached.

3. **Event Resolution**:
   - The event creator acts as the oracle and submits the outcome to the contract.
   - A dispute period allows users to challenge the reported outcome.

4. **Payout Distribution**:
   - Loot from losing bets is redistributed to winners.
   - Protocol fees are deducted.

5. **Collateral Release**:
   - If no disputes arise, the event creator's collateral is released.
   - If disputes occur, the collateral may be used to compensate affected users.

### 4.2 Betting Pools

- For each event, separate betting pools are established for each outcome.
- The total amount staked across all pools cannot exceed $\( L_{\text{max}} \)$.

### 4.3 Fee Structure

- **Betting Fee**: No fee is charged when placing bets.
- **Winning Fee**: A 1% fee is charged on the loot before distribution to winners.
- **Fee Allocation**:
  - **Event Creator**: Receives 0.5% of the loot as compensation for providing the outcome.
  - **Protocol**: Receives 0.5% of the loot for maintenance and development.

### 4.4 Token Support

- **Supported Tokens**: Major stablecoins (e.g., USDT, USDC) are used to minimize volatility.
- **Token Standard**: ERC-20 tokens facilitate seamless integration with wallets and exchanges.

---

## 5. Smart Contract Design

### 5.1 Contract Overview

The Pepper Protocol consists of several smart contracts:

- **Event Factory Contract**: Deploys new event contracts.
- **Event Contract**: Manages betting, outcome reporting, and payout distribution for a specific event.
- **Collateral Manager**: Handles collateral deposits and releases.
- **Governance Contract**: Manages protocol parameters and handles disputes.

### 5.2 Event Factory Contract

- **Functionality**:
  - Allows any user to create an event by depositing collateral.
  - Sets event parameters: description, outcomes, start and end times, and collateral amount.
- **Access Control**:
  - Open to all users, enhancing decentralization.
- **Parameters**:
  - **Collateral Requirement**: Ensures event creators have a stake in the event's integrity.
  - **Betting Limit**: Determined by the collateral and protocol-defined multiplier $\( m \)$.

### 5.3 Event Contract

Each event contract handles:

- **Bet Placement**:
  - Users place bets by transferring tokens to the contract.
  - Records user bets with details of the amount and chosen outcome.
  - Checks that total bets do not exceed $\( L_{\text{max}} \)$.

- **Odds Calculation**:
  - Recalculates odds after each bet based on the mathematical model.
  - Provides real-time odds to users.

- **Event Resolution**:
  - The event creator submits the outcome after the event concludes.
  - Implements a time-stamped submission to prevent manipulation.

- **Payout Distribution**:
  - After the dispute period, payouts are calculated and distributed.
  - Protocol fees are deducted accordingly.

- **Dispute Handling**:
  - Users can dispute the outcome within a predefined period.
  - If disputes are resolved against the event creator, their collateral may be forfeited.

### 5.4 Collateral Management

- **Collateral Deposit**:
  - Event creators deposit collateral $\( C \)$ when creating an event.
  - Stored securely in the Collateral Manager contract.

- **Betting Limit Calculation**:
  - $\( L_{\text{max}} = C \times m \)$
  - Multiplier \( m \) is set by the protocol to balance risk and participation.

- **Collateral Release**:
  - Released back to the event creator after successful event resolution and dispute period.
  - If disputes are upheld, collateral may be used to compensate affected users.

---

## 6. Oracle Integration

### 6.1 Event Resolution

- **Event Creator as Oracle**:
  - Event creators submit the outcome directly to the contract.
  - They are incentivized to provide accurate results to retrieve their collateral.

- **Data Submission**:
  - Must include verifiable evidence (e.g., links to official results).
  - Time-stamped and recorded on-chain.

- **Dispute Period**:
  - Users have a predefined period (e.g., 48 hours) to dispute the outcome.
  - Disputes are handled via the governance mechanism.

### 6.2 Dispute Resolution Mechanism

- **Dispute Initiation**:
  - Users stake a dispute fee to challenge the reported outcome.
  - Must provide evidence contradicting the event creator's submission.

- **Governance Intervention**:
  - Disputes are escalated to the governance contract.
  - Token holders vote on the valid outcome.

- **Outcome of Disputes**:
  - If the dispute is upheld:
    - Event creator's collateral is used to compensate winners.
    - Event creator may be penalized or banned from future event creation.
  - If the dispute is rejected:
    - Disputing user forfeits the dispute fee.
    - Fee is distributed to the event creator and protocol.

---

## 7. Governance

### 7.1 Protocol Governance

- **Governance Token**:
  - Native token used for voting and staking in dispute resolutions.
  - Encourages community participation.

- **Voting Mechanism**:
  - Token holders can vote on protocol upgrades, fee adjustments, and dispute outcomes.

- **Proposal Submission**:
  - Any token holder can submit proposals or improvements.

### 7.2 Event Creator Governance

- **Reputation System**:
  - Event creators build reputation based on past accuracy and dispute history.
  - High-reputation creators may require less collateral or receive higher betting limits.

- **Collateral Adjustment**:
  - Protocol may adjust collateral requirements based on the creator's reputation.

- **Sanctions**:
  - Creators providing false outcomes may face penalties, including loss of collateral and bans.

---

## 8. Security Considerations

### 8.1 Smart Contract Security

- **Audits**:
  - Contracts are audited by reputable firms to identify vulnerabilities.

- **Formal Verification**:
  - Critical components undergo formal verification to ensure correctness.

- **Upgradeable Contracts**:
  - Implement proxy patterns to allow for secure upgrades when necessary.

### 8.2 Economic Security

- **Collateral Requirements**:
  - Discourages malicious behavior by event creators.
  - Limits the maximum potential loss.

- **Betting Limits**:
  - Ensures the total staked amount does not exceed the collateral-backed limit.

- **Anti-Manipulation Measures**:
  - Monitoring for unusual betting patterns.
  - Sybil resistance mechanisms to prevent fake disputes.

### 8.3 Regulatory Compliance

- **KYC/AML Policies**:
  - Optional identity verification for large transactions or as required by law.

- **Jurisdictional Restrictions**:
  - Implement geo-fencing to comply with regional gambling laws.

- **Transparent Operations**:
  - Open-source code and transparent governance enhance trust and compliance.

---

## 9. Implementation Details

### 9.1 Blockchain Platform

- **Platform Choice**:
  - Built on Base or compatible EVM blockchain.

- **Scalability Solutions**:
  - Utilize Layer 2 solutions like Optimistic Rollups or zk-Rollups to reduce gas costs.

- **Interoperability**:
  - Cross-chain compatibility to expand user base and liquidity.

### 9.2 User Interface

- **Web and Mobile Applications**:
  - Intuitive interfaces for event creation, betting, and dispute management.

- **Real-Time Updates**:
  - Live odds and betting activity displayed to users.

- **Accessibility**:
  - Multilingual support and accessibility features.

### 9.3 Wallet Integration

- **Wallet Support**:
  - Integration with Coinbase Wallet, MetaMask, WalletConnect, and other popular wallets.

- **Secure Transactions**:
  - Users sign transactions securely through their wallets.

- **Balance Management**:
  - Real-time display of token balances and betting history.

---

## 10. Conclusion

The Pepper Gambling Protocol revolutionizes peer-to-peer betting by leveraging blockchain technology to create a decentralized, transparent, and fair platform. By allowing anyone to create events and act as the oracle, the protocol empowers users while maintaining security through collateral requirements. The mathematical models ensure equitable odds and payouts, even for events with multiple outcomes. Robust governance and dispute resolution mechanisms safeguard the integrity of the platform, making Pepper a pioneering solution in the decentralized gambling space.

---

## 11. References

1. **Uniswap v3 Core** - Hayden Adams et al., 2021.
2. **Automated Market Makers** - Abraham Othman, 2012.
3. **Decentralized Oracle Systems** - Sergey Nazarov et al., 2020.
4. **Smart Contract Security** - ConsenSys Diligence, 2021.

---

## 12. Disclaimer

This white paper is for informational purposes only and does not constitute financial, legal, or investment advice. The Pepper Gambling Protocol is subject to regulatory compliance and may not be available in all jurisdictions. Users should consult with legal professionals before engaging with the protocol. Betting involves financial risk, and users should bet responsibly. The protocol disclaims any liability for losses incurred by users.

---
