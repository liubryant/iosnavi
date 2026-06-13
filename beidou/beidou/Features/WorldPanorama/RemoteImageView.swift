//
//  RemoteImageView.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  简单远程图片视图。
//

import UIKit

final class RemoteImageView: UIImageView {
    private var task: URLSessionDataTask?

    func setImage(named imageName: String, fallbackURL: URL) {
        task?.cancel()
        contentMode = .scaleAspectFill

        if let localImage = UIImage(named: imageName) {
            image = localImage
            tintColor = nil
            return
        }

        setImage(url: fallbackURL)
    }

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
