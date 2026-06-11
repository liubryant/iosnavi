//
//  RemoteImageView.swift
//  beidou
//
//  简单远程图片视图。
//

import UIKit

final class RemoteImageView: UIImageView {
    private var task: URLSessionDataTask?

    func setImage(url: URL) {
        task?.cancel()
        image = UIImage(systemName: "photo")
        tintColor = .tertiaryLabel
        contentMode = .scaleAspectFill

        task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.image = image
            }
        }
        task?.resume()
    }

    deinit {
        task?.cancel()
    }
}
