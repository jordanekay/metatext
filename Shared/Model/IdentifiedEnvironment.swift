// Copyright © 2020 Metabolist. All rights reserved.

import Foundation
import Combine

class IdentifiedEnvironment {
    @Published var identity: Identity
    let observationErrors: AnyPublisher<Error, Never>

    private let networkClient: MastodonClient
    private let appEnvironment: AppEnvironment
    private let observationErrorsInput = PassthroughSubject<Error, Never>()
    private var cancellables = Set<AnyCancellable>()

    init(identityID: String, appEnvironment: AppEnvironment) throws {
        self.appEnvironment = appEnvironment
        observationErrors = observationErrorsInput.eraseToAnyPublisher()
        networkClient = MastodonClient(configuration: appEnvironment.URLSessionConfiguration)
        networkClient.accessToken = try appEnvironment.secrets.item(.accessToken, forIdentityID: identityID)

        let observation = appEnvironment.identityDatabase.identityObservation(id: identityID).share()

        var initialIdentity: Identity?

        observation.first().sink(
            receiveCompletion: { _ in },
            receiveValue: { initialIdentity = $0 })
            .store(in: &cancellables)

        guard let identity = initialIdentity else { throw IdentityDatabaseError.identityNotFound }

        self.identity = identity
        networkClient.instanceURL = identity.url

        observation.catch { [weak self] error -> Empty<Identity, Never> in
            self?.observationErrorsInput.send(error)

            return Empty()
        }
        .assign(to: &$identity)
    }
}

extension IdentifiedEnvironment {
    var isAuthorized: Bool { networkClient.accessToken != nil }

    func verifyCredentials() -> AnyPublisher<Void, Error> {
        networkClient.request(AccountEndpoint.verifyCredentials)
            .continuingIfWeakReferenceIsStillAlive(to: self)
            .map { ($0, $1.identity.id) }
            .flatMap(appEnvironment.identityDatabase.updateAccount)
            .eraseToAnyPublisher()
    }

    func refreshServerPreferences() -> AnyPublisher<Void, Error> {
        networkClient.request(PreferencesEndpoint.preferences)
            .continuingIfWeakReferenceIsStillAlive(to: self)
            .map { ($1.identity.preferences.updated(from: $0), $1.identity.id) }
            .flatMap(appEnvironment.identityDatabase.updatePreferences)
            .eraseToAnyPublisher()
    }

    func refreshInstance() -> AnyPublisher<Void, Error> {
        networkClient.request(InstanceEndpoint.instance)
            .continuingIfWeakReferenceIsStillAlive(to: self)
            .map { ($0, $1.identity.id) }
            .flatMap(appEnvironment.identityDatabase.updateInstance)
            .eraseToAnyPublisher()
    }

    func identitiesObservation() -> AnyPublisher<[Identity], Error> {
        appEnvironment.identityDatabase.identitiesObservation()
    }

    func recentIdentitiesObservation() -> AnyPublisher<[Identity], Error> {
        appEnvironment.identityDatabase.recentIdentitiesObservation(excluding: identity.id)
    }

    func updatePreferences(_ preferences: Identity.Preferences) -> AnyPublisher<Void, Error> {
        appEnvironment.identityDatabase.updatePreferences(preferences, forIdentityID: identity.id)
    }
}