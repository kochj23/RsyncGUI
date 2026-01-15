//
//  TestProgressView.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import SwiftUI

/// Simple test view to verify sheet presentation
struct TestProgressView: View {
    let job: SyncJob
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("TEST PROGRESS VIEW")
                .font(.largeTitle)
                .foregroundColor(.red)

            Text("Job: \(job.name)")
                .font(.title)

            Text("Source: \(job.source)")
            Text("Destination: \(job.destination)")

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(minWidth: 800, idealWidth: 800, maxWidth: 800,
               minHeight: 600, idealHeight: 600, maxHeight: 600)
        .fixedSize()
        .padding()
        .background(Color.white)
    }
}
