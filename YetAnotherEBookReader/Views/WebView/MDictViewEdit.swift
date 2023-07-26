//
//  MDictViewEdit.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/7/26.
//

import Foundation
import UIKit

class MDictViewEdit: UIViewController {
    static let kHintTableViewCellIdentifier = "io.github.dsreader.mdict.hint.cell"
    
    var editTextHints: [String] = []
    let editTextView = UITextField()
    let editTextHintView = UITableView()
    var commitWord: String? = nil
    
    var server: String?
    
    override func viewDidLoad() {
        editTextView.translatesAutoresizingMaskIntoConstraints = false
        editTextView.borderStyle = .roundedRect
        editTextView.backgroundColor = .clear
        self.view.addSubview(editTextView)
        NSLayoutConstraint.activate([
            editTextView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            editTextView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.9),
            editTextView.topAnchor.constraint(equalTo: view.topAnchor),
            editTextView.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        editTextView.addTarget(self, action: #selector(commitAction), for: .primaryActionTriggered)
        editTextView.addTarget(self, action: #selector(hintAction), for: .editingChanged)

        editTextHintView.translatesAutoresizingMaskIntoConstraints = false
        editTextHintView.backgroundColor = .clear
        self.view.addSubview(editTextHintView)
        NSLayoutConstraint.activate([
            editTextHintView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            editTextHintView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.95),
            editTextHintView.topAnchor.constraint(equalTo: editTextView.bottomAnchor, constant: 16),
            editTextHintView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
        editTextHintView.dataSource = self
        editTextHintView.delegate = self
        editTextHintView.register(UITableViewCell.self, forCellReuseIdentifier: MDictViewEdit.kHintTableViewCellIdentifier)
        
        self.navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                title: "Commit",
                style: .plain,
                target: self,
                action: #selector(commitAction)
            )
        ]
    }
    
    override func viewWillAppear(_ animated: Bool) {
        commitWord = editTextView.text
        super.viewWillAppear(animated)
        
        hintAction(self)
    }
    
    @objc func commitAction(_ sender: Any?) {
        self.commitWord = self.editTextView.text
        self.navigationController?.popViewController(animated: true)
    }
    
    @objc func hintAction(_ sender: Any?) {
        guard let word = editTextView.text,
              word.isEmpty == false,
              let server = server,
              var urlComponent = URLComponents(string: server.replacingOccurrences(of: "/lookup", with: "/hint"))
        else {
            editTextHints.removeAll()
            editTextHintView.reloadData()
            return
        }
        
        urlComponent.queryItems = [
            .init(name: "word", value: word.lowercased())
        ]
        
        guard let url = urlComponent.url else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard self.editTextView.text == word else { return }
            
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let result = try JSONDecoder().decode([String: [String]].self, from: data)
                    guard let prefixed = result["prefixed"] else { return }
                    guard self.editTextView.text == word else { return }
                    
                    self.editTextHints = prefixed
                    self.editTextHintView.reloadData()
                } catch {
                    
                }
            }
        }
    }
}

extension MDictViewEdit: UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        editTextHints.count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellView = tableView.dequeueReusableCell(withIdentifier: MDictViewEdit.kHintTableViewCellIdentifier, for: indexPath)
        
        cellView.contentView.subviews.forEach {
            $0.removeFromSuperview()
        }
        cellView.backgroundColor = .clear
        cellView.contentView.backgroundColor = .clear
        
        let label = UILabel()
        label.text = editTextHints[indexPath.row]
        label.textColor = editTextHintView.tintColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        cellView.contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: cellView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            label.widthAnchor.constraint(equalTo: cellView.widthAnchor),
            label.heightAnchor.constraint(equalTo: cellView.heightAnchor)
        ])
        
        return cellView
    }
}

extension MDictViewEdit: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.editTextView.text = editTextHints[indexPath.row]
        commitAction(self)
    }
}
