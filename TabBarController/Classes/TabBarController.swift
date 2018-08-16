//
//  TabBarController.swift
//  TabBarController
//
//  Created by Arnaud Dorgans on 14/08/2018.
//

import UIKit

@objc public protocol TabBarControllerDelegate: class {
    @objc optional func tabBarController(_ tabBarController: TabBarController, shouldSelect viewController: UIViewController) -> Bool
    @objc optional func tabBarController(_ tabBarController: TabBarController, didSelect viewController: UIViewController)
    @objc optional func tabBarController(_ tabBarController: TabBarController, animationControllerFrom fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning?
    @objc optional func tabBarController(_ tabBarController: TabBarController, animateTabBar animations: ()->Void)
}

enum TabBarControllerUpdateSource {
    case action
    case update
}

open class TabBarController: UIViewController {
    
    @IBOutlet public weak var delegate: TabBarControllerDelegate?
    @IBOutlet public weak var tabBar: TabBar!
    
    private lazy var containerController = TabBarContainerController(tabBarController: self)
    private lazy var tabBarContainer = TabBarContainer(tabBarController: self)
    
    private var _viewControllers: [UIViewController]?
    public var viewControllers: [UIViewController]? {
        get { return _viewControllers }
        set {
            _viewControllers = newValue
            updateViewControllers()
        }
    }
    
    private var _selectedIndex: Int = 0
    public var selectedIndex: Int {
        get { return _selectedIndex }
        set {
            _selectedIndex = newValue
            updateSelectedController(source: .action)
        }
    }
    
    public var isTabBarHidden: Bool {
        return tabBarContainer.isTabBarHidden
    }
    
    @IBInspectable var prefersAdditionalInset: Bool = false {
        didSet {
            updateInset()
        }
    }
    
    public var selectedViewController: UIViewController? {
        guard let viewControllers = viewControllers, selectedIndex < viewControllers.count else {
            return nil
        }
        return viewControllers[selectedIndex]
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        
        let tabBar = self.tabBar ?? SystemTabBar()
        self.tabBar = tabBar
        self.tabBar?.delegate = self
        tabBarContainer.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(tabBarContainer)
        tabBarContainer.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        tabBarContainer.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        tabBarContainer.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        
        containerController.willMove(toParentViewController: self)
        containerController.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.insertSubview(containerController.view, at: 0)
        containerController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        containerController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        containerController.view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        containerController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        self.addChildViewController(containerController)
        containerController.didMove(toParentViewController: self)
    }
    
    // MARK: TabBar
    public func setTabBarHidden(_ hidden: Bool, animated: Bool) {
        func update() {
            self.tabBarContainer.setTabBarHidden(hidden)
            self.updateInset()
        }
        if animated {
            guard self.delegate?.tabBarController?(self, animateTabBar: update) == nil else {
                return
            }
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut, animations: update, completion: nil)
        } else {
            update()
        }
    }
    
    // MARK: ViewControllers
    public func setViewControllers(_ viewControllers: [UIViewController]?) {
        self._viewControllers = viewControllers
        self.updateViewControllers()
    }
    
    private func updateViewControllers() {
        self._viewControllers = self._viewControllers?.map { NavContainerController(controller: $0, tabBarController: self) ?? $0 }
        self.tabBar?.setItems(viewControllers.flatMap { $0.map { $0.tabBarItem } }, animated: false)
        updateSelectedController(source: .update)
    }
    
    open func update(viewController: UIViewController) {
        self.setNeedsStatusBarAppearanceUpdate()
        if #available(iOS 11.0, *) {
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
        self.setTabBarHidden(viewController.hidesBottomBarWhenPushed, animated: false)
        updateInset(viewController: viewController)
    }
    
    // MARK: SelectedController
    private func updateSelectedController(source: TabBarControllerUpdateSource) {
        guard let viewControllers = self.viewControllers, !viewControllers.isEmpty else {
            containerController.setViewController(nil, source: source)
            self._selectedIndex = 0
            return
        }
        self._selectedIndex = max(0, min(viewControllers.count - 1, selectedIndex))
        containerController.setViewController(viewControllers[selectedIndex], source: source)
        self.tabBar?.selectedItem = self.selectedViewController?.tabBarItem
    }
    
    // MARK: ChildViewController
    open override var childViewControllerForStatusBarStyle: UIViewController? {
        return containerController
    }
    
    open override var childViewControllerForStatusBarHidden: UIViewController? {
        return containerController
    }
    
    open override func childViewControllerForHomeIndicatorAutoHidden() -> UIViewController? {
        return containerController
    }
}

extension TabBarController: TabBarDelegate {
    
    public func tabBar(_ tabBar: TabBar, didSelect item: UITabBarItem) {
        guard let index = self.viewControllers?.index(where: { $0.tabBarItem == item }),
            let controller = self.viewControllers?[index] else {
            return
        }
        guard self.delegate?.tabBarController?(self, shouldSelect: controller) != false else {
            updateSelectedController(source: .update)
            return
        }
        if index != self.selectedIndex {
            self.selectedIndex = index
            guard let selectedViewController = self.selectedViewController else {
                return
            }
            self.delegate?.tabBarController?(self, didSelect: selectedViewController)
        } else {
            (self.selectedViewController as? TabBarChildControllerProtocol)?.tabBarAction?()
        }
    }
}

// MARK: Transitions
extension TabBarController: UINavigationControllerDelegate {
    
    public func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        update(navigationController: navigationController, viewController: viewController, animated: animated)
    }
    
    public func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        update(navigationController: navigationController, viewController: viewController, animated: animated)
    }
    
    private func update(navigationController: UINavigationController, viewController: UIViewController, animated: Bool) {
        guard let transitionCoordinator = navigationController.transitionCoordinator, animated else {
            self.update(viewController: viewController)
            return
        }
        transitionCoordinator.notifyWhenInteractionEnds { [unowned self] context in
            guard let viewController = context.viewController(forKey: .from), context.isCancelled else {
                return
            }
            self.update(viewController: viewController)
        }
        transitionCoordinator.animate(alongsideTransition: { [unowned self] context in
            guard let viewController = context.viewController(forKey: .to) else {
                return
            }
            self.update(viewController: viewController)
        }, completion: nil)
    }
    
    private func updateInset(viewController: UIViewController? = nil) {
        if #available(iOS 11.0, *) {
            containerController.additionalSafeAreaInsets.bottom = !self.prefersAdditionalInset ? tabBarContainer.additionalInset : 0
            containerController.viewSafeAreaInsetsDidChange()
        }
        let inset: CGFloat = {
            if #available(iOS 11.0, *), !self.prefersAdditionalInset {
                return 0
            }
            return tabBarContainer.additionalInset
        }()
        (containerController.viewController as? TabBarChildControllerProtocol)?.updateAllConstraints(inset)
        (viewController as? TabBarChildControllerProtocol)?.updateAllConstraints(inset)
    }
}

extension TabBarController: TabBarContainerDelegate {
    
    func tabBarContainer(_ tabBarContainer: TabBarContainer, didUpdateAdditionalInset inset: CGFloat) {
        updateInset()
    }
}

extension TabBarController: TabBarContainerControllerDelegate {
    
    func tabBarContainerController(_ TabBarContainerController: TabBarContainerController, animationControllerFrom fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return self.delegate?.tabBarController?(self, animationControllerFrom: fromVC, to: toVC)
    }
    
    func tabBarContainerController(_ TabBarContainerController: TabBarContainerController, willShow viewController: UIViewController?) {
        updateInset(viewController: viewController)
    }
}
