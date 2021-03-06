//
//  ViewController.swift
//  standardnotes
//
//  Created by Mo Bitar on 12/19/16.
//  Copyright © 2016 Standard Notes. All rights reserved.
//

import UIKit
import CoreData

enum SortType: Int {
    case Created = 0
    case Modified = 1
    case Title = 2
    case TypeCount
}

class NotesViewController: UIViewController {

    @IBOutlet weak var tableView: UITableView!
    var searchBar: UISearchBar!
    
    var sort: SortType {
        get {
            return SortType(rawValue: UserDefaults.standard.integer(forKey: "SortType"))!
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "SortType")
            UserDefaults.standard.synchronize()
        }
    }
    
    var resultsController: NSFetchedResultsController<Note>!
    var selectedTags = [Tag]()
    var refreshControl: UIRefreshControl!
   
    override func viewDidLoad() {
        super.viewDidLoad()
        configureTableView()
        configureNavBar()
        reloadResults()
        
        // fixes dark gray shadow during vc transition
        self.navigationController?.view.backgroundColor = UIColor.white
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIApplicationWillEnterForeground, object: nil, queue: OperationQueue.main) { (notification) in
            self.refreshItems()
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: UserManager.LogoutNotification), object: nil, queue: OperationQueue.main) { (notification) in
            self.reloadResults()
        }
        
        // search bar loading triggers resultsController for some reason, so it must be done at the end
        searchBar = UISearchBar(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: 44))
        searchBar.delegate = self
        tableView.tableHeaderView = self.searchBar
    }
    
    func configureTableView() {
        self.tableView.rowHeight = UITableViewAutomaticDimension
        self.tableView.estimatedRowHeight = 90
     
        refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.addSubview(refreshControl)
    }
    
    func refresh() {
        refreshItems()
    }
    
    func configureNavBar() {
        let tagsTitle = selectedTags.count > 0 ? "Filter (\(selectedTags.count))" : "Filter"
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: tagsTitle, style: .plain, target: self, action: #selector(tagsPressed))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "New", style: .plain, target: self, action: #selector(newPressed))
    }
    
    var viewDidDisappear = false
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshItems()
        if viewDidDisappear {
            viewDidDisappear = false
                self.sync()
        }
        
        if(!didHideSearchBar) {
            tableView.setContentOffset(CGPoint(x:0, y:self.searchBar.frame.size.height), animated: false)
            didHideSearchBar = true
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(true)
        viewDidDisappear = true
    }
    
    var didHideSearchBar = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }
    
    func refreshItems() {
        if !UserManager.sharedInstance.signedIn {
            return
        }
        
        ApiController.sharedInstance.sync { (error) in
            self.refreshControl.endRefreshing()
        }
    }
    
    func tagsPressed() {
        let tags = self.storyboard?.instantiateViewController(withIdentifier: "Tags") as! TagsViewController
        tags.hasSortType = true
        tags.sort = sort
        tags.setInitialSelectedTags(tags: self.selectedTags)
        tags.selectionCompletion = { tags, sort in
            self.sort = sort!
            self.selectedTags = tags
            self.reloadResults()
            self.configureNavBar()
        }
        
        let navController = UINavigationController(rootViewController: tags)
        self.present(navController, animated: true, completion: nil)
    }
    
    func newPressed() {
        presentComposer(note: nil)
    }
    
    func presentComposer(note: Note?) {
        let compose = self.storyboard?.instantiateViewController(withIdentifier: "Compose") as! ComposeViewController
        compose.note = note        
        self.navigationController?.pushViewController(compose, animated: true)
    }
    
    func sortKey() -> String {
        switch sort {
        case .Created:
            return "createdAt"
        case .Modified:
            return "updatedAt"
        case .Title:
            return "title"
        default:
            return "createdAt"
        }
    }
    
    func reloadResults() {
        let fetchRequest = NSFetchRequest<Note>(entityName: "Note")
        fetchRequest.predicate = NSPredicate(format: "draft == false")
        var predicates = [NSPredicate]()
        
        // handle the case of search text is entered
        if searchBar != nil, let searchText = searchBar.text, searchText != "" {
            if selectedTags.count > 0 { // tags also selected
                var selectedUUIDs = [String]()
                for tag in selectedTags {
                    selectedUUIDs += [tag.uuid]
                }
                let searchPredicate = NSPredicate(format: "(ANY tags.uuid in %@) AND ((title contains[cd] %@) OR (text contains[cd] %@) OR (tags.title contains %@))",selectedUUIDs,searchText,searchText,searchText)
                predicates.append(searchPredicate)
            } else {
                let searchPredicate = NSPredicate(format: "(title contains[cd] %@) OR (text contains[cd] %@) OR (tags.title contains[cd] %@)",searchText,searchText,searchText)
                predicates.append(searchPredicate)
            }
        } else { // handle tags
            for tag in selectedTags {
                let tagPredicate = NSPredicate(format: "ANY tags.uuid == %@", tag.uuid)
                predicates.append(tagPredicate)
            }
        }

//        if sort == .Title {
//            fetchRequest.sortDescriptors = [NSSortDescriptor(key: sortKey(), ascending: true, selector: #selector(NSString.caseInsensitiveCompare(_:)))]
//        } else {
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: sortKey(), ascending: sort == .Title ? true : false)]
//        }
        
        if predicates.count > 0 {
            let searchPredicates = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [fetchRequest.predicate!, searchPredicates])
        }
        
        resultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: AppDelegate.sharedContext, sectionNameKeyPath: nil, cacheName: nil)
    
        resultsController.delegate = self
        do {
            try resultsController.performFetch()
            self.tableView.reloadData()
        }
        catch {
            print("Error fetching: \(error)")
        }
    }
    
    func presentActionSheetForNote(note: Note) {
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
    
        let cell = self.tableView.cellForRow(at: self.resultsController.indexPath(forObject: note)!)
        alertController.popoverPresentationController?.sourceView = cell
                
        let deleteAction = UIAlertAction(title: "Delete", style: .destructive, handler: {
            alert -> Void in
            self.showDestructiveAlert(title: "Confirm Deletion", message: "Are you sure you want to delete this note?", buttonString: "Delete", block: { 
                self.deleteNote(note: note)
            })
        })
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: {
            (action : UIAlertAction!) -> Void in
            
        })
        
        alertController.addAction(deleteAction)
        alertController.addAction(cancelAction)
        
        self.present(alertController, animated: true, completion: nil)
    }
    
    func deleteNote(note: Note) {
        ItemManager.sharedInstance.setItemToBeDeleted(item: note)
        ApiController.sharedInstance.sync { (error) in
            if error == nil {
                ItemManager.sharedInstance.removeItemFromCoreData(item: note)
            } else {
                self.showAlert(title: "Oops", message: "There was an error deleting your note. Please try again.")
            }
        }
    }
}

/**
   Notes searching functions
 */
extension NotesViewController: UISearchBarDelegate {

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        navigationController?.setNavigationBarHidden(true, animated: true)
        searchBar.showsCancelButton = true
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        navigationController?.setNavigationBarHidden(false, animated: true)
        searchBar.showsCancelButton = false
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        reloadResults()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
}

extension NotesViewController : UITableViewDelegate, UITableViewDataSource {
    
    func configureCell(cell: NoteTableViewCell, indexPath: NSIndexPath) {
        // check if out of bounds
        let sectionInfo = resultsController.sections![indexPath.section]
        if sectionInfo.numberOfObjects <= indexPath.row {
            return
        }
        let selectedObject = resultsController.object(at: indexPath as IndexPath) as Note
		if selectedObject.errorDecrypting {
			cell.titleLabel?.text = "Error decrypting"
		} else {
			cell.titleLabel?.text = selectedObject.safeTitle()
		}
        cell.contentLabel?.text = selectedObject.safeText()
        cell.dateLabel?.text = selectedObject.humanReadableCreateDate()
        cell.note = selectedObject
		
        cell.longPressHandler = { cell in
            self.presentActionSheetForNote(note: cell.note)
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "NoteCell", for: indexPath) as! NoteTableViewCell
        configureCell(cell: cell, indexPath: indexPath as NSIndexPath)
        return cell
    }
    
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return resultsController.sections!.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = resultsController.sections else {
            fatalError("No sections in fetchedResultsController")
        }
        let sectionInfo = sections[section]
        return sectionInfo.numberOfObjects
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
        let selectedObject = resultsController.object(at: indexPath as IndexPath) as Note
		if selectedObject.errorDecrypting {
			self.showAlert(title: "Unable to Decrypt", message: "There was an error decrypting this item. Ensure you are running the latest version of this app, then sign out and sign back in to try again.")
			return
		}
        presentComposer(note: selectedObject)
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if (editingStyle == .delete) {
            let selectedNote = resultsController.object(at: indexPath as IndexPath) as Note
            deleteNote(note: selectedNote)
        }
    }
}

extension NotesViewController : NSFetchedResultsControllerDelegate {
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        switch type {
        case .insert:
            tableView.insertSections(NSIndexSet(index: sectionIndex) as IndexSet, with: .fade)
        case .delete:
            tableView.deleteSections(NSIndexSet(index: sectionIndex) as IndexSet, with: .fade)
        case .move:
            break
        case .update:
            break
        }
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            tableView.insertRows(at: [newIndexPath! as IndexPath], with: .fade)
        case .delete:
            tableView.deleteRows(at: [indexPath! as IndexPath], with
                : .fade)
        case .update:
            if let cell = tableView.cellForRow(at: indexPath! as IndexPath) as? NoteTableViewCell {
                configureCell(cell: cell, indexPath: indexPath! as NSIndexPath)
                tableView.reloadRows(at: [indexPath!], with: .none)
            }
        case .move:
            tableView.moveRow(at: indexPath! as IndexPath, to: newIndexPath! as IndexPath)
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }
}

