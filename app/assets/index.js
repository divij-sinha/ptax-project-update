
var button = document.getElementById("search-button");

// debounce to create smoother search suggestions
let debounceTimeout;
function debounce(func, delay) {
    return function (...args) {
        clearTimeout(debounceTimeout);
        debounceTimeout = setTimeout(() => func.apply(this, args), delay);
    };
}


document.addEventListener('DOMContentLoaded', function () {
    let selectedIndex = -1;
    let suggestions = [];

    // Debounce function (you'll need to implement this or use a library like lodash)
    const debounce = (func, delay) => {
        let timeout;
        return function () {
            const context = this;
            const args = arguments;
            clearTimeout(timeout);
            timeout = setTimeout(() => func.apply(context, args), delay);
        };
    };

    const searchTermInput = document.getElementById('search_term');
    const searchTermHidden = document.getElementById('search_term_hidden');
    const suggestionsDropdown = document.getElementById('suggestions_dropdown');


    searchTermInput.addEventListener('input', debounce(function () {
        const searchTerm = this.value.toUpperCase();

        if (searchTerm.length >= 2) {
            fetch('/address_suggestions', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded', // Or 'application/json' if sending JSON
                },
                body: `search_term=${searchTerm}`, // Or JSON.stringify({...})
            })
                .then(response => response.json())
                .then(response => {
                    suggestions = response;
                    let dropdownHtml = "";
                    response.forEach(function (suggestion, index) {
                        dropdownHtml += `<a class="dropdown-item" href="#" data-index="${index}" data-hidden-value="${suggestion.value}">${suggestion.key}</a>`;
                    });
                    suggestionsDropdown.innerHTML = dropdownHtml;
                    suggestionsDropdown.classList.add('show');
                    selectedIndex = -1;
                });
        } else {
            suggestionsDropdown.classList.remove('show');
        }
    }, 200));

    document.addEventListener('click', function (event) {
        if (event.target.classList.contains('dropdown-item')) {
            searchTermInput.value = event.target.textContent;
            searchTermHidden.value = event.target.dataset.hiddenValue;
            suggestionsDropdown.classList.remove('show');
        }
    });


    searchTermInput.addEventListener('focusout', function () {
        if (!suggestionsDropdown.matches(':hover')) {  // Use matches for modern browsers
            suggestionsDropdown.classList.remove('show');
        }
    });

    searchTermInput.addEventListener('keydown', function (e) {
        const items = suggestionsDropdown.querySelectorAll('.dropdown-item');

        if (e.key === 'ArrowDown') {
            e.preventDefault();
            if (selectedIndex < items.length - 1) {
                selectedIndex++;
                items.forEach(item => item.classList.remove('active'));
                items[selectedIndex].classList.add('active');
            }
        } else if (e.key === 'ArrowUp') {
            e.preventDefault();
            if (selectedIndex > 0) {
                selectedIndex--;
                items.forEach(item => item.classList.remove('active'));
                items[selectedIndex].classList.add('active');
            }
        } else if (e.key === 'Enter') {
            e.preventDefault();
            if (selectedIndex >= 0) {
                searchTermInput.value = items[selectedIndex].textContent;
                searchTermHidden.value = items[selectedIndex].dataset.hiddenValue;
                suggestionsDropdown.classList.remove('show');
            }
        }
    });
});