//
//  PhotoAuthorizationRepository.swift
//  PhotoSearch
//
//  Created by G.K.LEE on 11/14/25.
//

import Photos

enum PhotoAuthorizationState {
    case notDetermined
    case authorized      // .authorized 또는 .limited
    case denied          // .denied, .restricted 등
}

protocol PhotoAuthorizationRepository {
    func currentStatus() -> PhotoAuthorizationState
    func requestAuthorizationIfNeeded() async -> PhotoAuthorizationState
}

final class DefaultPhotoAuthorizationRepository: PhotoAuthorizationRepository {

    func currentStatus() -> PhotoAuthorizationState {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized, .limited:
            return .authorized
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func requestAuthorizationIfNeeded() async -> PhotoAuthorizationState {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            switch newStatus {
            case .authorized, .limited:
                return .authorized
            case .denied, .restricted:
                return .denied
            case .notDetermined:
                return await requestAuthorizationIfNeeded()
            @unknown default:
                return .denied
            }
        case .authorized, .limited:
            return .authorized
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }
}
