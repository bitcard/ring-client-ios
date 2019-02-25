/*
 *  Copyright (C) 2017-2019 Savoir-faire Linux Inc.
 *
 *  Author: Silbino Gonçalves Matado <silbino.gmatado@savoirfairelinux.com>
 *  Author: Quentin Muret <quentin.muret@savoirfairelinux.com>
 *  Author: Kateryna Kostiuk <kateryna.kostiuk@savoirfairelinux.com>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301 USA.
 */

import UIKit
import RxSwift
import RxDataSources
import RxCocoa
import Reusable
import SwiftyBeaver

//Constants
private struct SmartlistConstants {
    static let smartlistRowHeight: CGFloat = 64.0
    static let tableHeaderViewHeight: CGFloat = 24.0
    static let firstSectionHeightForHeader: CGFloat = 31.0 //Compensate the offset due to the label on the top of the tableView
    static let defaultSectionHeightForHeader: CGFloat = 55.0
}

class SmartlistViewController: UIViewController, StoryboardBased, ViewModelBased {

    private let log = SwiftyBeaver.self

    // MARK: outlets
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var conversationsTableView: UITableView!
    @IBOutlet weak var searchResultsTableView: UITableView!
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var noConversationsView: UIView!
    @IBOutlet weak var noConversationLabel: UILabel!
    @IBOutlet weak var searchTableViewLabel: UILabel!
    @IBOutlet weak var networkAlertLabel: UILabel!
    @IBOutlet weak var cellularAlertLabel: UILabel!
    @IBOutlet weak var networkAlertViewTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var settingsButton: UIButton!

    // account selection
    var accounPicker = UIPickerView()
    let accountPickerTextView = UITextField(frame: CGRect.zero)
    let accountsAdapter = AccountPickerAdapter()
    var accountsDismissTapRecognizer: UITapGestureRecognizer!

    // MARK: members
    var viewModel: SmartlistViewModel!
    fileprivate let disposeBag = DisposeBag()

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }

    // MARK: functions
    @IBAction func openScan() {
        self.viewModel.showQRCode()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupDataSources()
        self.setupTableViews()
        self.setupSearchBar()
        self.setupUI()
        self.applyL10n()
        self.configureRingNavigationBar()
        self.confugureAccountPicker()
        accountsDismissTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))

        /*
         Register to keyboard notifications to adjust tableView insets when the keybaord appears
         or disappears
         */
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(withNotification:)), name: NSNotification.Name.UIKeyboardDidShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(withNotification:)), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
    }

    @objc func dismissKeyboard() {
        accountPickerTextView.resignFirstResponder()
        view.removeGestureRecognizer(accountsDismissTapRecognizer)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.navigationBar.layer.shadowColor = UIColor.clear.cgColor
        self.navigationController?.navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        self.navigationController?.navigationBar
            .titleTextAttributes = [NSAttributedStringKey.font: UIFont(name: "HelveticaNeue-Light", size: 25)!,
                                    NSAttributedStringKey.foregroundColor: UIColor.jamiMain]
        if let text = searchBar.text, !text.isEmpty {
            self.searchBar.setShowsCancelButton(true, animated: false)
            if let cancelButton = searchBar.value(forKey: "cancelButton") as? UIButton {
                cancelButton.isEnabled = true
            }
        }
    }

    func applyL10n() {
        self.navigationItem.title = L10n.Global.homeTabBarTitle
        noConversationLabel.text = L10n.Smartlist.noConversation
        self.searchBar.placeholder = L10n.Smartlist.searchBarPlaceholder
        self.networkAlertLabel.text = L10n.Smartlist.noNetworkConnectivity
        self.cellularAlertLabel.text = L10n.Smartlist.cellularAccess
    }

    func setupUI() {
        self.viewModel.hideNoConversationsMessage
            .bind(to: self.noConversationsView.rx.isHidden)
            .disposed(by: disposeBag)

        self.networkAlertViewTopConstraint.constant = self.viewModel.networkConnectionState() == .none ? 0.0 : -56.0
        self.viewModel.connectionState
            .subscribe(onNext: { connectionState in
                let newAlertHeight = connectionState == .none ? 0.0 : -56.0
                UIView.animate(withDuration: 0.25) {
                    self.networkAlertViewTopConstraint.constant = CGFloat(newAlertHeight)
                    self.view.layoutIfNeeded()
                }
            })
            .disposed(by: self.disposeBag)

        self.settingsButton.backgroundColor = nil
        self.settingsButton.rx.tap.subscribe(onNext: { _ in
            if let url = URL(string: UIApplicationOpenSettingsURLString) {
                if #available(iOS 10.0, *) {
                    UIApplication.shared.open(url, completionHandler: nil)
                } else {
                    UIApplication.shared.openURL(url)
                }
            }
        }).disposed(by: self.disposeBag)

        let imageScanSearch = UIImage(asset: Asset.qrCodeScan) as UIImage?
        let scanButton   = UIButton(type: UIButtonType.custom) as UIButton
        scanButton.setImage(imageScanSearch, for: .normal)
        let scanButtonItem = UIBarButtonItem(customView: scanButton)
        scanButton.rx.tap.throttle(0.5, scheduler: MainScheduler.instance)
            .subscribe(onNext: { [unowned self] in
                self.openScan()
            })
            .disposed(by: self.disposeBag)

        self.navigationItem.rightBarButtonItem = scanButtonItem

        //create accounts button
        let expendAccountButton = UIButton(type: .custom)
        expendAccountButton.frame = CGRect(x: 40, y: 0, width: 40, height: 40)
        expendAccountButton.setTitle("....", for: .normal)
        expendAccountButton.setTitleColor(.jamiSecondary, for: .normal)
        let accountButton = UIButton(type: .custom)
        self.viewModel.profileImage.bind(to: accountButton.rx.image(for: .normal))
            .disposed(by: disposeBag)
        accountButton.roundedCorners = true
        accountButton.cornerRadius = 20
        accountButton.clipsToBounds = true
        accountButton.contentMode = .scaleAspectFill
        accountButton.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        accountButton.imageEdgeInsets = UIEdgeInsets(top: -4, left: -4, bottom: -4, right: -4)
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 40))
        containerView.addSubview(expendAccountButton)
        containerView.addSubview(accountButton)
        let accountButtonItem = UIBarButtonItem(customView: containerView)
        accountButtonItem.customView?.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 10.0, *) {
            accountButtonItem.customView?.heightAnchor.constraint(equalToConstant: 40).isActive = true
            accountButtonItem.customView?.widthAnchor.constraint(equalToConstant: 80).isActive = true
        }
        accountButton.rx.tap.throttle(0.5, scheduler: MainScheduler.instance)
            .subscribe(onNext: { [unowned self] in
                self.openAccountsList()
            })
            .disposed(by: self.disposeBag)
        expendAccountButton.rx.tap.throttle(0.5, scheduler: MainScheduler.instance)
            .subscribe(onNext: { [unowned self] in
                self.openAccountsList()
            })
            .disposed(by: self.disposeBag)

        self.navigationItem.leftBarButtonItem = accountButtonItem
    }

    func confugureAccountPicker() {
        view.addSubview(accountPickerTextView)
        accountPickerTextView.inputView = accounPicker
        accounPicker.backgroundColor = .jamiNavigationBar
        self.viewModel.accounts
            .observeOn(MainScheduler.instance)
            .bind(to: accounPicker.rx.items(adapter: accountsAdapter))
            .disposed(by: disposeBag)
        if let account = self.viewModel.currentAccount,
            let row = accountsAdapter.rowForAccountId(account: account) {
            accounPicker.selectRow(row, inComponent: 0, animated: true)
        }
        self.viewModel.currentAccountChanged
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [unowned self] currentAccount in
                if let account = currentAccount,
                    let row = self.accountsAdapter.rowForAccountId(account: account) {
                    self.accounPicker.selectRow(row, inComponent: 0, animated: true)
                }
            }).disposed(by: disposeBag)
        accounPicker.rx.modelSelected(AccountItem.self)
            .subscribe(onNext: { [weak self] model in
                let account = model[0].account
                self?.viewModel.changeCurrentAccount(accountId: account.id)
            })
            .disposed(by: disposeBag)
        let accountsLabel = UILabel(frame: CGRect(x: 0, y: 20, width: self.view.frame.width, height: 40))
        accountsLabel.text = L10n.Smartlist.accountsTitle
        accountsLabel.font = UIFont.systemFont(ofSize: 25, weight: .light)
        accountsLabel.textColor = .jamiSecondary
        accountsLabel.textAlignment = .center
        let addAccountButton = UIButton(type: .custom)
        addAccountButton.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        addAccountButton.contentHorizontalAlignment = .right
        addAccountButton.setTitle(L10n.Smartlist.addAccountButton, for: .normal)
        addAccountButton.setTitleColor(.jamiMain, for: .normal)
        addAccountButton.titleLabel?.font = UIFont(name: "HelveticaNeue-Light", size: 25)
        let flexibleBarButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.flexibleSpace, target: self, action: nil)
        let addBarButton = UIBarButtonItem(customView: addAccountButton)
        let toolbar = UIToolbar()
        toolbar.barTintColor = .jamiNavigationBar
        toolbar.isTranslucent = false
        toolbar.sizeToFit()
        toolbar.center = CGPoint(x: self.view.frame.width * 0.5, y: 200)
        toolbar.items = [flexibleBarButton, addBarButton]
        accountPickerTextView.inputAccessoryView = toolbar
        addAccountButton.rx.tap
            .throttle(0.5, scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] in
                self?.startAccountCreation()
            })
            .disposed(by: self.disposeBag)
    }

    @objc func keyboardWillShow(withNotification notification: Notification) {
        let userInfo: Dictionary = notification.userInfo!
        guard let keyboardFrame: NSValue = userInfo[UIKeyboardFrameEndUserInfoKey] as? NSValue else { return }
        let keyboardRectangle = keyboardFrame.cgRectValue
        let keyboardHeight = keyboardRectangle.height
        let tabBarHeight = (self.tabBarController?.tabBar.frame.size.height)!

        self.conversationsTableView.contentInset.bottom = keyboardHeight - tabBarHeight
        self.searchResultsTableView.contentInset.bottom = keyboardHeight - tabBarHeight
        self.conversationsTableView.scrollIndicatorInsets.bottom = keyboardHeight - tabBarHeight
        self.searchResultsTableView.scrollIndicatorInsets.bottom = keyboardHeight - tabBarHeight
    }

    @objc func keyboardWillHide(withNotification notification: Notification) {
        self.conversationsTableView.contentInset.bottom = 0
        self.searchResultsTableView.contentInset.bottom = 0

        self.conversationsTableView.scrollIndicatorInsets.bottom = 0
        self.searchResultsTableView.scrollIndicatorInsets.bottom = 0
    }

    func setupDataSources() {
        //Configure cells closure for the datasources
        let configureCell: (TableViewSectionedDataSource, UITableView, IndexPath, ConversationSection.Item)
            -> UITableViewCell = {
                (   dataSource: TableViewSectionedDataSource<ConversationSection>,
                    tableView: UITableView,
                    indexPath: IndexPath,
                    conversationItem: ConversationSection.Item) in

                let cell = tableView.dequeueReusableCell(for: indexPath, cellType: ConversationCell.self)
                cell.configureFromItem(conversationItem)
                return cell
        }

        //Create DataSources for conversations and filtered conversations
        let conversationsDataSource = RxTableViewSectionedReloadDataSource<ConversationSection>(configureCell: configureCell)
        let searchResultsDatasource = RxTableViewSectionedReloadDataSource<ConversationSection>(configureCell: configureCell)

        //Allows to delete
        conversationsDataSource.canEditRowAtIndexPath = { _, _  in
            return true
        }

        //Bind TableViews to DataSources
        self.viewModel.conversations
            .bind(to: self.conversationsTableView.rx.items(dataSource: conversationsDataSource))
            .disposed(by: disposeBag)

        self.viewModel.searchResults
            .bind(to: self.searchResultsTableView.rx.items(dataSource: searchResultsDatasource))
            .disposed(by: disposeBag)

        //Set header titles
        searchResultsDatasource.titleForHeaderInSection = { dataSource, index in
            return dataSource.sectionModels[index].header
        }
    }

    func setupTableViews() {
        //Set row height
        self.conversationsTableView.rowHeight = SmartlistConstants.smartlistRowHeight
        self.searchResultsTableView.rowHeight = SmartlistConstants.smartlistRowHeight

        //Register Cell
        self.conversationsTableView.register(cellType: ConversationCell.self)
        self.searchResultsTableView.register(cellType: ConversationCell.self)

        //Bind to ViewModel to show or hide the filtered results
        self.viewModel.isSearching.subscribe(onNext: { [unowned self] (isSearching) in
            self.searchResultsTableView.isHidden = !isSearching
        }).disposed(by: disposeBag)

        //Deselect the rows
        self.conversationsTableView.rx.itemSelected.subscribe(onNext: { [unowned self] indexPath in
            self.conversationsTableView.deselectRow(at: indexPath, animated: true)
        }).disposed(by: disposeBag)

        self.searchResultsTableView.rx.itemSelected.subscribe(onNext: { [unowned self] indexPath in
            self.searchResultsTableView.deselectRow(at: indexPath, animated: true)
        }).disposed(by: disposeBag)

        //Bind the search status label
        self.viewModel.searchStatus
            .observeOn(MainScheduler.instance)
            .bind(to: self.searchTableViewLabel.rx.text)
            .disposed(by: disposeBag)

        self.searchResultsTableView.rx.setDelegate(self).disposed(by: disposeBag)
        self.conversationsTableView.rx.setDelegate(self).disposed(by: disposeBag)
    }

    func setupSearchBar() {

        self.searchBar.returnKeyType = .done
        self.searchBar.autocapitalizationType = .none
        self.searchBar.tintColor = UIColor.jamiMain
        self.searchBar.barTintColor =  UIColor.jamiNavigationBar

        self.view.bringSubview(toFront: self.searchBar)

        self.searchBar.layer.shadowColor = UIColor.black.cgColor
        self.searchBar.layer.shadowOffset = CGSize(width: 0.0, height: 2.5)
        self.searchBar.layer.shadowOpacity = 0.2
        self.searchBar.layer.shadowRadius = 3
        self.searchBar.layer.masksToBounds = false

        //Bind the SearchBar to the ViewModel
        self.searchBar.rx.text.orEmpty
            .debounce(Durations.textFieldThrottlingDuration.value, scheduler: MainScheduler.instance)
            .bind(to: self.viewModel.searchBarText)
            .disposed(by: disposeBag)

        //Show Cancel button
        self.searchBar.rx.textDidBeginEditing.subscribe(onNext: { [unowned self] in
            self.searchBar.setShowsCancelButton(true, animated: true)
        }).disposed(by: disposeBag)

        //Hide Cancel button
        self.searchBar.rx.textDidEndEditing.subscribe(onNext: { [unowned self] in
            self.searchBar.setShowsCancelButton(false, animated: true)
        }).disposed(by: disposeBag)

        //Cancel button event
        self.searchBar.rx.cancelButtonClicked.subscribe(onNext: { [unowned self] in
            self.cancelSearch()
        }).disposed(by: disposeBag)

        //Search button event
        self.searchBar.rx.searchButtonClicked.subscribe(onNext: { [unowned self] in
            self.searchBar.resignFirstResponder()
        }).disposed(by: disposeBag)
    }

    func cancelSearch() {
        self.searchBar.text = ""
        self.searchBar.resignFirstResponder()
        self.searchResultsTableView.isHidden = true
    }

    func startAccountCreation() {
        accountPickerTextView.resignFirstResponder()
        self.viewModel.createAccount()
    }

    func openAccountsList() {
        if searchBar.isFirstResponder {
            return
        }
        if accountPickerTextView.isFirstResponder {
            accountPickerTextView.resignFirstResponder()
            return
        }
        accountPickerTextView.becomeFirstResponder()
        self.view.addGestureRecognizer(accountsDismissTapRecognizer)
    }

    private func showClearConversationConfirmation(atIndex: IndexPath) {
        let alert = UIAlertController(title: L10n.Alerts.confirmClearConversationTitle, message: L10n.Alerts.confirmClearConversation, preferredStyle: .alert)
        let deleteAction = UIAlertAction(title: L10n.Actions.clearAction, style: .destructive) { (_: UIAlertAction!) -> Void in
            if let convToDelete: ConversationViewModel = try? self.conversationsTableView.rx.model(at: atIndex) {
                self.viewModel.clear(conversationViewModel: convToDelete)
            }
        }
        let cancelAction = UIAlertAction(title: L10n.Actions.cancelAction, style: .default) { (_: UIAlertAction!) -> Void in }
        alert.addAction(deleteAction)
        alert.addAction(cancelAction)
        self.present(alert, animated: true, completion: nil)
    }

    private func showRemoveConversationConfirmation(atIndex: IndexPath) {
        let alert = UIAlertController(title: L10n.Alerts.confirmDeleteConversationTitle, message: L10n.Alerts.confirmDeleteConversation, preferredStyle: .alert)
        let deleteAction = UIAlertAction(title: L10n.Actions.deleteAction, style: .destructive) { (_: UIAlertAction!) -> Void in
            if let convToDelete: ConversationViewModel = try? self.conversationsTableView.rx.model(at: atIndex) {
                self.viewModel.delete(conversationViewModel: convToDelete)
            }
        }
        let cancelAction = UIAlertAction(title: L10n.Actions.cancelAction, style: .default) { (_: UIAlertAction!) -> Void in }
        alert.addAction(deleteAction)
        alert.addAction(cancelAction)
        self.present(alert, animated: true, completion: nil)
    }

    private func showBlockContactConfirmation(atIndex: IndexPath) {
        let alert = UIAlertController(title: L10n.Alerts.confirmBlockContactTitle, message: L10n.Alerts.confirmBlockContact, preferredStyle: .alert)
        let blockAction = UIAlertAction(title: L10n.Actions.blockAction, style: .destructive) { (_: UIAlertAction!) -> Void in
            if let conversation: ConversationViewModel = try? self.conversationsTableView.rx.model(at: atIndex) {
                self.viewModel.blockConversationsContact(conversationViewModel: conversation)
            }
        }
        let cancelAction = UIAlertAction(title: L10n.Actions.cancelAction, style: .default) { (_: UIAlertAction!) -> Void in }
        alert.addAction(blockAction)
        alert.addAction(cancelAction)
        self.present(alert, animated: true, completion: nil)
    }
}

extension SmartlistViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 0 {
            if tableView == self.conversationsTableView {
                return 0
            }
            return SmartlistConstants.firstSectionHeightForHeader
        } else {
            return SmartlistConstants.defaultSectionHeightForHeader
        }
    }

    func tableView(_ tableView: UITableView, editActionsForRowAt: IndexPath) -> [UITableViewRowAction]? {
        let block = UITableViewRowAction(style: .normal, title: "Block") { _, index in
            self.showBlockContactConfirmation(atIndex: index)
        }
        block.backgroundColor = .red

        let delete = UITableViewRowAction(style: .normal, title: "Delete") { _, index in
            self.showRemoveConversationConfirmation(atIndex: index)
        }
        delete.backgroundColor = .orange

        let clear = UITableViewRowAction(style: .normal, title: "Clear") { _, index in
            self.showClearConversationConfirmation(atIndex: index)
        }
        clear.backgroundColor = .magenta

        return [clear, delete, block]
    }

    private func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if self.navigationController?.topViewController == self {
            if let convToShow: ConversationViewModel = try? tableView.rx.model(at: indexPath) {
                self.viewModel.showConversation(withConversationViewModel: convToShow)
            }
        }
    }
}
