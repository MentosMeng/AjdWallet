// Copyright © 2020 Stormbird PTE. LTD.

import Foundation
import RealmSwift
import PromiseKit

protocol EventsDataStoreProtocol {
    func getLastMatchingEventSortedByBlockNumber(forContract contract: AlphaWallet.Address, tokenContract: AlphaWallet.Address, server: RPCServer, eventName: String) -> Promise<EventInstanceValue?>
    func add(events: [EventInstanceValue], forTokenContract contract: AlphaWallet.Address)
    func deleteEvents(forTokenContract contract: AlphaWallet.Address)
    func getMatchingEvent(forContract contract: AlphaWallet.Address, tokenContract: AlphaWallet.Address, server: RPCServer, eventName: String, filterName: String, filterValue: String) -> EventInstance?
    func subscribe(_ subscribe: @escaping (_ contract: AlphaWallet.Address) -> Void)
}

//TODO rename to indicate it's for instances, not activity
class EventsDataStore: EventsDataStoreProtocol {
    private let realm: Realm
    private var subscribers: [(AlphaWallet.Address) -> Void] = []

    init(realm: Realm) {
        self.realm = realm
    }

    func subscribe(_ subscribe: @escaping (_ contract: AlphaWallet.Address) -> Void) {
        subscribers.append(subscribe)
    }

    private func triggerSubscribers(forContract contract: AlphaWallet.Address) {
        subscribers.forEach { $0(contract) }
    }

    func getMatchingEvent(forContract contract: AlphaWallet.Address, tokenContract: AlphaWallet.Address, server: RPCServer, eventName: String, filterName: String, filterValue: String) -> EventInstance? {
        let predicate = EventsDataStore
            .functional
            .matchingEventPredicate(forContract: contract, tokenContract: tokenContract, server: server, eventName: eventName, filterName: filterName, filterValue: filterValue)

        return realm.objects(EventInstance.self)
            .filter(predicate)
            .first
    }

    func deleteEvents(forTokenContract contract: AlphaWallet.Address) {
        let events = getEvents(forTokenContract: contract)
        delete(events: events)
    }

    private func getEvents(forTokenContract tokenContract: AlphaWallet.Address) -> Results<EventInstance> {
        realm.objects(EventInstance.self)
                .filter("tokenContract = '\(tokenContract.eip55String)'")
    }

    private func delete<S: Sequence>(events: S) where S.Element: EventInstance {
        try? realm.write {
            realm.delete(events)
        }
    }

    func getLastMatchingEventSortedByBlockNumber(forContract contract: AlphaWallet.Address, tokenContract: AlphaWallet.Address, server: RPCServer, eventName: String) -> Promise<EventInstanceValue?> {
        return Promise { seal in
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return seal.reject(PMKError.cancelled) }
                let predicate = EventsDataStore
                    .functional
                    .matchingEventPredicate(forContract: contract, tokenContract: tokenContract, server: server, eventName: eventName)

                let event = Array(strongSelf.realm.objects(EventInstance.self)
                    .filter(predicate)
                    .sorted(byKeyPath: "blockNumber"))
                    .map { EventInstanceValue(event: $0) }
                    .last

                seal.fulfill(event)
            }
        }
    }

    func add(events: [EventInstanceValue], forTokenContract contract: AlphaWallet.Address) {
        guard !events.isEmpty else { return }
        let eventsToSave = events.map { EventInstance(event: $0) }

        realm.beginWrite()
        realm.add(eventsToSave, update: .all)
        try? realm.commitWrite()
        triggerSubscribers(forContract: contract)
    }
}

extension EventsDataStore {
    enum functional {}
}

extension EventsDataStore.functional {

    static func isFilterMatchPredicate(filterName: String, filterValue: String) -> NSPredicate {
        return NSPredicate(format: "filter = '\(filterName)=\(filterValue)'")
    }

    static func matchingEventPredicate(forContract contract: AlphaWallet.Address, tokenContract: AlphaWallet.Address, server: RPCServer, eventName: String, filterName: String, filterValue: String) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            EventsActivityDataStore.functional.isContractMatchPredicate(contract: contract),
            EventsActivityDataStore.functional.isChainIdMatchPredicate(server: server),
            EventsActivityDataStore.functional.isTokenContractMatchPredicate(contract: tokenContract),
            EventsActivityDataStore.functional.isEventNameMatchPredicate(eventName: eventName),
            isFilterMatchPredicate(filterName: filterName, filterValue: filterValue)
        ])
    }

    static func matchingEventPredicate(forContract contract: AlphaWallet.Address, tokenContract: AlphaWallet.Address, server: RPCServer, eventName: String) -> NSPredicate {
        EventsActivityDataStore.functional.matchingEventPredicate(forContract: contract, tokenContract: tokenContract, server: server, eventName: eventName)
    }
}

