import StoreKit
import SwiftUI

/// Buying Arch Premium, restoring it, and hearing about it changing.
///
/// **Premium used to be free.** The subscribe button was
/// `settings.isSubscribed.toggle()`: it switched Premium on in memory, charged
/// nothing, told the server nothing, and was gone the next launch. Nothing in the
/// app imported StoreKit, and nothing on the server ever wrote `subscriptions`.
///
/// **The server decides, not the phone.** A purchase is sent to the
/// `subscription` function, which asks Apple directly and records what Apple
/// says; that record is what the matcher reads for seven slots and what the
/// location allowance reads. So this class never grants Premium itself. It tells
/// the server what happened and reports what the server answered.
///
/// A transaction is finished only once the server has it. If the server cannot
/// be reached, StoreKit keeps the transaction open and hands it back on the next
/// launch -- which is the retry. A purchase can be late; it cannot be lost.
@MainActor
@Observable
final class Purchases {

    static let shared = Purchases()

    /// Plan ids as the screen knows them, against product ids as App Store
    /// Connect must spell them. **These three have to exist in App Store Connect
    /// with exactly these ids**, as auto-renewable subscriptions in one group, or
    /// the Premium screen has nothing to sell.
    static let catalogue: [(plan: String, product: String)] = [
        ("p1", "com.arch.arch.premium.1m"),
        ("p3", "com.arch.arch.premium.3m"),
        ("p12", "com.arch.arch.premium.12m"),
    ]

    private(set) var products: [String: Product] = [:]
    private(set) var isWorking = false
    /// Something to say about the last thing the reader asked for. Never set by
    /// anything that happens in the background.
    private(set) var problem: String?

    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var onChange: (Bool) -> Void = { _ in }

    /// Once somebody is signed in. Safe to call again.
    ///
    /// Listens for transactions that arrive outside a purchase -- renewals, Ask
    /// to Buy approvals, a subscription bought on another device -- and then
    /// re-confirms whatever this Apple ID already owns, which is what heals a
    /// purchase that reached Apple and not the server.
    func start(onChange: @escaping (Bool) -> Void) async {
        self.onChange = onChange
        listen()
        await loadProducts()
        await confirmEntitlements(speaking: false)
    }

    /// The plans to show, priced by Apple in the reader's own currency.
    ///
    /// Empty until the products load, and empty for good if they do not exist in
    /// App Store Connect or the Paid Applications agreement is not active -- in
    /// which case the screen says Premium is not available rather than showing a
    /// price nobody can pay.
    var plans: [PremiumPlan] {
        Self.catalogue.compactMap { entry in
            guard let product = products[entry.plan],
                  let period = product.subscription?.subscriptionPeriod else { return nil }
            let months = Self.months(in: period)
            let each = product.price / Decimal(months)
            return PremiumPlan(
                id: entry.plan,
                duration: Self.duration(months),
                total: product.displayPrice,
                perMonth: "\(each.formatted(product.priceFormatStyle)) a month",
                isRecommended: entry.plan == "p3"
            )
        }
    }

    /// Asks again if nothing has loaded yet. The agreement can become active
    /// while the app is open, and the Premium tab is where that would show.
    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let loaded = try await Product.products(for: Self.catalogue.map(\.product))
            var byPlan: [String: Product] = [:]
            for entry in Self.catalogue {
                if let product = loaded.first(where: { $0.id == entry.product }) {
                    byPlan[entry.plan] = product
                }
            }
            products = byPlan
        } catch {
            print("[purchases] could not load products: \(error)")
        }
    }

    // MARK: Buying

    func purchase(planID: String) async {
        guard let product = products[planID] else {
            problem = "Arch Premium isn't available to buy right now."
            return
        }
        // The account id travels with the purchase. Apple keeps it on every
        // renewal, and it is what lets the server refuse to put one person's
        // subscription on somebody else's account.
        guard let session = await SupabaseClient.shared.restore(),
              let account = UUID(uuidString: session.userID) else {
            problem = "Sign in again, then subscribe."
            return
        }

        isWorking = true
        problem = nil
        defer { isWorking = false }

        do {
            switch try await product.purchase(options: [.appAccountToken(account)]) {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    problem = "That purchase couldn't be verified. Try Restore purchases."
                    return
                }
                await confirm(transaction, speaking: true)
            case .userCancelled:
                break
            case .pending:
                // Ask to Buy, or a payment method that needs attention. It
                // arrives later through `Transaction.updates`.
                problem = "Waiting for approval. Premium starts as soon as it's approved."
            @unknown default:
                break
            }
        } catch {
            problem = "The purchase didn't go through."
        }
    }

    func restore() async {
        isWorking = true
        problem = nil
        defer { isWorking = false }

        // Asks the reader to sign in to their Apple ID if it needs to. Cancelling
        // that is not a failure worth reporting.
        do { try await AppStore.sync() } catch { return }

        let owned = await confirmEntitlements(speaking: true)
        if !owned {
            problem = "There's no Arch Premium on this Apple ID to restore."
        }
    }

    // MARK: Confirming

    // `StoreKit.Transaction` in full, everywhere in this file. SwiftUI has a
    // `Transaction` of its own -- the one that carries an animation -- and with
    // both imported the bare name is ambiguous. The build said so.
    private func listen() {
        guard updates == nil else { return }
        updates = Task { @MainActor [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await self?.confirm(transaction, speaking: false)
            }
        }
    }

    /// Whether this Apple ID owns any Arch subscription at all, confirming each.
    @discardableResult
    private func confirmEntitlements(speaking: Bool) async -> Bool {
        var owned = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.catalogue.contains(where: { $0.product == transaction.productID })
            else { continue }
            owned = true
            await confirm(transaction, speaking: speaking)
        }
        return owned
    }

    /// Tells the server, then finishes the transaction.
    ///
    /// Finished only on an answer. A server that could not be reached leaves it
    /// open for StoreKit to hand back; a server that *refused* it -- the purchase
    /// belongs to another Arch account -- finishes it, because no retry will ever
    /// change that answer and an unfinished transaction is redelivered forever.
    private func confirm(_ transaction: StoreKit.Transaction, speaking: Bool) async {
        do {
            let status = try await ArchBackend.syncSubscription(
                originalTransactionID: String(transaction.originalID)
            )
            await transaction.finish()
            onChange(status.active)
        } catch ArchAPIError.notPermitted {
            await transaction.finish()
            if speaking {
                problem = "This Apple ID's Premium belongs to a different Arch account."
            }
        } catch {
            if speaking {
                problem = "Your purchase went through, but Arch couldn't confirm it yet. "
                    + "It will be applied as soon as it can."
            }
        }
    }

    // MARK: Words

    private static func months(in period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .year:  return period.value * 12
        case .month: return max(period.value, 1)
        // Weeks and days are not sold. Counted as one so nothing divides by zero
        // if one is ever added by mistake.
        default:     return 1
        }
    }

    private static func duration(_ months: Int) -> String {
        switch months {
        case 1:  return "One month"
        case 3:  return "Three months"
        case 6:  return "Six months"
        case 12: return "Twelve months"
        default: return "\(months) months"
        }
    }
}
