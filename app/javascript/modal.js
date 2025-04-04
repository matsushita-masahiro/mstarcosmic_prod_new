function closeModal(elem) {
    var modal = document.getElementById('reserveModal');
    
    window.addEventListener('click', function(e) {
      if (e.target == modal) {
        modal.style.display = 'none';
      }
    });
    
    if (elem.className == "close"){
        modal.style.display = 'none';
    }
    
}

console.log("modal.js");