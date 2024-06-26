==================
Native tokens FAQs
==================

On-chain assets
===============

**Q. What’s the definition of ‘multi-asset (MA)’ support and does
Cardano have it?**

A. Multi-asset (MA) support is the name of a feature set (functionality)
that a ledger (blockchain/wallet/cryptocurrency/banking platform) can
provide, which allows it to do accounting on or transact with more than
one type of asset.

Cardano’s MA support feature is called Native Tokens. MA allows users to
transact with ada and an unlimited number of user-defined tokens. This
support is native, which means that tokens can be transacted with
(tracked/sent/received) using the accounting system defined as part of
the ledger functionality of the cryptocurrency, without the need for
smart contracts to enable this functionality.

**Q. What is (asset) tokenization?**

A. Tokenizing an asset means creating an on-chain representation of that
asset.

Minting
=======

**Q. What does ‘minting’ a token mean?**

A.’Minting’ refers to the process whereby new tokens are created or
destroyed. That is, the total amount in circulation (ie. added up over
all addresses on the ledger) of the token type being minted increases or
decreases. Minting a positive quantity of tokens is token creation, and
minting a negative quantity is token destruction.

**Q. What does ‘burning’ a token mean?**

A.’Burning’ refers to the process whereby tokens are destroyed. It is
synonymous with ‘negative minting’.

**Q. What is token redeeming?**

A. Token redeeming is the action of sending tokens back to the issuer to
be burned. This is usually done when the tokens being redeemed no longer
have a purpose on the ledger, and the user or contract in possession of
them is not able (not unauthorized by the minting policy) to burn the
tokens.

There may not be any compensation offered for redeeming the tokens
(deciding this is up to the token issuer/minting policy), but the user
may choose to do so anyway to avoid having unusable tokens in their
wallet.

**Q. What is a minting transaction?**

A. Every ledger era starting with Mary contains a field in the transaction
body for minting multi-assets, named the mint field.
In order to use the minting field, transaction must be authorized by the
minting policy. Positive values create assets, and negative ones destroy them.

Note that a single transaction might mint tokens associated with
multiple distinct minting policies. e.g.,
``(Policy1, SomeTokens), (Policy2, SomeOtherTokens)``. Note also that a
transaction might simultaneously mint some tokens and burn some other
ones.

**Q. What is a minting policy?**

A. A minting policy is a set of rules used to regulate the minting of
assets associated with it (scoped under it). For example, who has
control (and under what conditions) over the supply of the currency, and
its minting and burning. These rules are about the content of the
transaction data of the transaction that is attempting the mint. e.g., a
minting policy can require a particular set of keys to have signed the
minting transaction.

This set of rules is defined by the user who wishes to create the new
asset. For example, a user might wish to only allow themselves to ever
mint this particular kind of token. In this case, they would stipulate
this in the policy. The node checks adherence to minting policies when a
transaction is processed by running the code or checking the relevant
signatures. Transaction data must satisfy all the minting policies of
all assets the transaction is attempting to mint.

Policy examples and ways to define policies
===========================================

**Q. What is ‘multisig’ and how is it related to minting policies?**

A. The multisig scripting language specifies some minimal set
of signatures required to allow a transaction to perform a certain
action, usually to spend a UTXO entry.

Multisig scripts can also be used to specify the most basic minting
policies, that is, the policies that require a specific set of keys to
sign the minting transaction. For example, a single-issuer minting
policy can be expressed using a multisig script. Note that minting
policies are the only types of policy that can be expressed using
multisig.

Without Plutus smart contract capability, or any other minting policy
language extensions, multisig is the only way to specify a minting
policy.

**Q. What do Plutus smart contracts have to do with native tokens?**

A. Minting policies can be written in the Plutus smart contract
language. This allows users to express a much wider range of policies
than just the single issuer policy expressible using multisig. The
one-time minting policy, for example, can be expressed in Plutus (but
not just as multisig).

**Q. What is a single-issuer minting policy?**

A. A single-issuer minting policy specifies that only the entity holding
a particular set of keys is allowed to mint tokens under a particular
policy. For example, the set of keys specified in the minting policy
must have signed the minting transaction. This type of policy can be
specified using multisig.

An example of a single-issuer policy use case could be tokens
representing baseball cards. This would mean that no new baseball card
tokens could be minted without the company’s signatures. Conversely, the
policy proves that all the existing cards scoped under this policy have
been legitimately minted by the baseball card company.

**Q. What is a one-time minting policy?**

A. In a one-time minting policy, the complete set of tokens scoped under
it is minted by one specific transaction. This means that no more tokens
will ever be minted under that policy. This type of policy does require
smart contracts and cannot be expressed using multisig.

A use case of a one-time minting policy would be minting ticket tokens
for a specific gig. The venue capacity is known ahead of time, so
there’ll be no need to ever allow more tickets to be minted.

Multi-asset structure, representation and properties
====================================================

**Q. What is fungibility and non-fungibility?**

A. Fungibility is a relation between two assets/tokens. Tokens are said
to be fungible with each other when they are interchangeable. For
example, fiat money is fungible as a $10 bill is interchangeable with
all other (real) $10 bills (and all 10-sets of $1 bills, and all pairs
of $5s).

Non-fungible assets are not interchangeable with each other. For
example, two diamonds, or two on-chain tokens representing the two
real-world diamonds. If there are no other assets a token is fungible
with -such as a token representing a house- the token is deemed to be
unique (non-fungible).

**Q. What is a token bundle?** A. A mixed collection of tokens scoped
under one or more minting policies. Any tokens can be bundled together.

For more detail, see the token bundle section.

Transacting with native tokens
==============================

**Q. What are the costs related to minting and trading native tokens?**

A. Costs related to multi assets can be divided into two categories:

-  **Fees**: Sending and minting tokens affects the fees that the author
   of the transaction must pay. As with an ada-only ledger, the fees are
   calculated based on the total size of the transaction. There might
   also be fees for checking minting policies, but initially only
   multisig policies are supported, which do not incur additional fees
   on top of the transaction size-based ones.

-  **Min-ada-value**: Every output created by a transaction must include
   a minimum amount of ada, which is calculated based on the size of the
   output (that is, the number of different token types in it, and the
   lengths of their names).

**Min-ada-value explanation:**

Remember that outputs may contain a heterogeneous collection of tokens,
including ada is a limited resource in the Cardano system. Requiring
some amount of ada be included in every output on the ledger (where that
amount is based on the size of the output, in bytes) protects the size
of the Cardano ledger from growing intractably.

**Q. What types of assets can I use to cover costs associated with
native tokens?**

A. Currently, only ada can be used to make fee payments or deposits.

**Q. Is it possible to send tokens to an address?**

A. Yes, sending native tokens to an address is done in the same way as
sending ada to an address, i.e., by submitting a transaction with
outputs containing the token bundles the transaction author wishes to
send, together with the addresses to which they are sent.

What control does the user have over custom token assets?
=========================================================

Users can spend, send, trade, or receive all types of MA tokens in the
same way as ada. Unlike ada, users can also mint and burn native tokens.

**Spending tokens** : Users can spend the tokens in their wallet, or
tokens in outputs locked by scripts that allow this user to spend the
output.

**Sending tokens to other users** : Users can send the tokens in their
wallets (or any tokens they can spend) to any address.

**Minting tokens** : Users can mint custom tokens according to the
policy associated with this asset. The minting transaction can place
these tokens in the user’s address, or anyone else’s. If necessary, the
policy can restrict the exact output location for the tokens.

Note that even if the user has defined a policy, that user might not be
able to mint or burn assets scoped under this policy, depending on the
policy rules. A minting policy controls the minting of all assets scoped
under it, regardless of the identity of the user who defined the policy.

**Burning tokens** : Burning tokens is also controlled by the policy
associated with the asset. Besides being allowed to burn the tokens
(always in accordance with the minting policy), the user must also be
able to spend the tokens they are attempting to burn. For example, if
the tokens are in their wallet).

Users cannot burn tokens over which they have no control, such as tokens
in someone else’s wallet, even if the minting policy would specifically
allow this.

**Q. Is there a Decentralized Exchange (DEX) for Cardano native
tokens?**

A. No. The Cardano ledger does not itself support DEX functionality.
However, when smart contract functionality is available, one can post
non-ada assets for exchange or sale on the ledger using a smart
contract.

**Q. Is there an asset registry for Cardano native tokens?**

A. No. The implementation of the Native Tokens feature on Cardano does
not require an asset registry. However, the metadata server (see “Do
assets have human-readable identifiers and other metadata?”) can be used
to list tokens a user has minted, if they wish to do so.

Cardano Native Tokens vs ERC
============================

**Q. How do Cardano native tokens compare to ERC721 and ERC20 Ethereum
custom tokens?**

A. Cardano’s approach to building custom tokens differs from a
non-native implementation of custom tokens, such as ERC721 or ERC20,
where custom tokens are implemented using smart contract functionality
to simulate transfer of custom assets (i.e., a ledger accounting
system). Our approach to create custom tokens does not require smart
contracts, as the ledger implementation itself supports the accounting
on non-ada native assets.

Another key difference is that Cardano multi-asset ledger supports both
fungible and non-fungible tokens without specialized contracts (unlike
ERC721 or ERC20), and is versatile enough to include a combination of
different types of fungible and non-fungible tokens in a single output.
