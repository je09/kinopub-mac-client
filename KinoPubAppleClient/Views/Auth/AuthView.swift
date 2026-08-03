//
//  AuthView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 24.07.2023.
//

import AppKit
import SwiftUI
import KinoPubUI

/// A full-window macOS activation experience. Native window controls remain the only close affordance;
/// the content follows the familiar sign-in layout of one focused task, one prominent action, and a
/// clearly selectable device code.
struct AuthView: View {

  @StateObject var model: AuthModel
  @EnvironmentObject var errorHandler: ErrorHandler
  @Environment(\.dismiss) private var dismiss
  @State private var copied = false

  init(model: @autoclosure @escaping () -> AuthModel) {
    _model = StateObject(wrappedValue: model())
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        activationIcon

        VStack(spacing: 8) {
          Text("Auth_CodeActivationTitle")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(Color.KinoPub.text)

          Text("Open the activation page, sign in to kino.pub, and enter this code.")
            .font(.body)
            .foregroundStyle(Color.KinoPub.subtitle)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }

        deviceCodePanel

        Button(action: model.openActivationURL) {
          Label("Open Activation Page", systemImage: "safari")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(model.deviceCode.isEmpty || model.verificationURL.isEmpty)

        activationStatus
      }
      .frame(maxWidth: 420)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 32)
      .padding(.vertical, 64)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    .interactiveDismissDisabled(true)
    .task { model.fetchDeviceCode() }
    .onReceive(model.$close) { shouldClose in
      if shouldClose { dismiss() }
    }
    .handleError(state: $errorHandler.state)
  }

  private var activationIcon: some View {
    Image(systemName: "play.rectangle.on.rectangle.fill")
      .symbolRenderingMode(.hierarchical)
      .font(.system(size: 42, weight: .medium))
      .foregroundStyle(Color.accentColor)
      .frame(width: 76, height: 76)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .accessibilityHidden(true)
  }

  private var deviceCodePanel: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Auth_DeviceCode")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.KinoPub.subtitle)

      if model.deviceCode.isEmpty {
        HStack(spacing: 10) {
          ProgressView().controlSize(.small)
          Text("Requesting a device code…")
            .foregroundStyle(Color.KinoPub.subtitle)
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
      } else {
        HStack(spacing: 16) {
          Text(model.deviceCode)
            .font(.system(size: 32, weight: .semibold, design: .monospaced))
            .tracking(4)
            .foregroundStyle(Color.KinoPub.text)
            .textSelection(.enabled)
            .accessibilityLabel("Device code")
            .accessibilityValue(model.deviceCode.map(String.init).joined(separator: " "))

          Spacer(minLength: 8)

          Button {
            model.copyCode()
            withAnimation(.easeInOut(duration: 0.15)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
              withAnimation(.easeInOut(duration: 0.15)) { copied = false }
            }
          } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
          }
          .buttonStyle(.bordered)
          .controlSize(.regular)
        }
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.08))
    }
  }

  @ViewBuilder
  private var activationStatus: some View {
    if !model.deviceCode.isEmpty {
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Waiting for activation…")
      }
      .font(.subheadline)
      .foregroundStyle(Color.KinoPub.subtitle)
      .accessibilityElement(children: .combine)
    }
  }
}
